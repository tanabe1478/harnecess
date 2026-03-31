#!/usr/bin/env bash
# state_watcher.sh — Watch queue/tasks/ and queue/reports/ for changes,
# automatically notify target agents via tmux and update state.
#
# This replaces the manual inbox_write + tmux send-keys workflow.
# Lead writes task YAML → state_watcher detects → notifies agent.
#
# Usage: bash scripts/state_watcher.sh
# Runs as a long-lived daemon. Kill with: pkill -f state_watcher.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE_DIR="${SCRIPT_DIR}/queue"
STATE_FILE="${QUEUE_DIR}/state.yaml"
HISTORY_FILE="${QUEUE_DIR}/state_history.yaml"
INBOX_WRITE="${SCRIPT_DIR}/scripts/inbox_write.sh"

# Agent → tmux pane mapping
declare -A AGENT_PANES=(
    [planner]="harnecess-agents:agents.0"
    [builder]="harnecess-agents:agents.1"
    [checker]="harnecess-agents:agents.2"
    [writer]="harnecess-agents:agents.3"
    [lead]="harnecess:main"
)

# Task file → agent mapping
declare -A TASK_AGENTS=(
    [planner.yaml]="planner"
    [builder.yaml]="builder"
    [checker.yaml]="checker"
    [writer.yaml]="writer"
)

# Report file → notify lead
declare -A REPORT_AGENTS=(
    [planner_report.yaml]="lead"
    [builder_report.yaml]="lead"
    [checker_report.yaml]="lead"
    [writer_report.yaml]="lead"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [state_watcher] $*" >&2
}

# Update state.yaml
update_state() {
    local new_state="$1"
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local current_state=""
    if [ -f "$STATE_FILE" ]; then
        current_state="$("${SCRIPT_DIR}/.venv/bin/python3" -c "
import yaml
with open('${STATE_FILE}') as f:
    d = yaml.safe_load(f) or {}
print(d.get('current_state', ''))
" 2>/dev/null || echo "")"
    fi

    "${SCRIPT_DIR}/.venv/bin/python3" -c "
import yaml, os

state_file = '${STATE_FILE}'
history_file = '${HISTORY_FILE}'
new_state = '${new_state}'
prev_state = '${current_state}'
timestamp = '${timestamp}'

# Update state
state = {
    'current_state': new_state,
    'previous_state': prev_state,
    'timestamp': timestamp,
}
with open(state_file, 'w') as f:
    yaml.dump(state, f, default_flow_style=False, allow_unicode=True)

# Append to history
entry = {'state': new_state, 'from': prev_state, 'timestamp': timestamp}
if os.path.exists(history_file):
    with open(history_file) as f:
        history = yaml.safe_load(f) or {'transitions': []}
else:
    history = {'transitions': []}
history['transitions'].append(entry)
with open(history_file, 'w') as f:
    yaml.dump(history, f, default_flow_style=False, allow_unicode=True)
" 2>/dev/null

    log "State: ${current_state} → ${new_state}"
}

# Notify an agent via inbox_write + tmux send-keys with retry
notify_agent() {
    local agent="$1"
    local pane="${AGENT_PANES[$agent]}"
    local message="$2"
    local max_retries=3
    local attempt=0

    # Write inbox message
    if [ -f "$INBOX_WRITE" ]; then
        bash "$INBOX_WRITE" "$agent" "$message" "task_assigned" "state_watcher" 2>/dev/null || true
    fi

    # Send tmux nudge with retry
    while [ $attempt -lt $max_retries ]; do
        attempt=$((attempt + 1))
        if tmux send-keys -t "$pane" "inbox1" Enter 2>/dev/null; then
            log "Notified ${agent} at ${pane} (attempt ${attempt})"
            return 0
        fi
        log "Notify ${agent} failed (attempt ${attempt}/${max_retries}), retrying..."
        sleep 3
    done

    log "WARNING: Failed to notify ${agent} after ${max_retries} attempts"
    return 1
}

# Process a file change event
process_event() {
    local filepath="$1"
    local filename
    filename="$(basename "$filepath")"
    local dirname
    dirname="$(basename "$(dirname "$filepath")")"

    # Ignore lock files, tmp files
    case "$filename" in
        *.lock|*.lock.d|*.tmp|*.swp) return ;;
    esac

    if [ "$dirname" = "tasks" ]; then
        # Task file changed → check if status is "assigned" → notify agent
        local agent="${TASK_AGENTS[$filename]:-}"
        if [ -z "$agent" ]; then
            return
        fi

        local status
        status="$("${SCRIPT_DIR}/.venv/bin/python3" -c "
import yaml
with open('${filepath}') as f:
    d = yaml.safe_load(f) or {}
task = d.get('task', d)
print(task.get('status', ''))
" 2>/dev/null || echo "")"

        if [ "$status" = "assigned" ]; then
            local task_id
            task_id="$("${SCRIPT_DIR}/.venv/bin/python3" -c "
import yaml
with open('${filepath}') as f:
    d = yaml.safe_load(f) or {}
task = d.get('task', d)
print(task.get('task_id', 'unknown'))
" 2>/dev/null || echo "unknown")"

            update_state "${agent}_working"
            notify_agent "$agent" "タスク ${task_id} が割り当てられました。queue/tasks/${filename} を確認せよ。"
        fi

    elif [ "$dirname" = "reports" ]; then
        # Report file changed → notify lead
        local notify_target="${REPORT_AGENTS[$filename]:-}"
        if [ -z "$notify_target" ]; then
            return
        fi

        local report_agent
        report_agent="$(echo "$filename" | sed 's/_report\.yaml//')"

        update_state "${report_agent}_done"
        notify_agent "lead" "${report_agent} から完了報告。queue/reports/${filename} を確認せよ。"
    fi
}

# --- Main ---

log "Starting state_watcher..."
log "Watching: ${QUEUE_DIR}/tasks/ and ${QUEUE_DIR}/reports/"

# Initialize state
mkdir -p "$(dirname "$STATE_FILE")"
update_state "idle"

# Detect OS and select watcher
if [ "$(uname -s)" = "Darwin" ]; then
    if ! command -v fswatch &>/dev/null; then
        log "ERROR: fswatch not found. Install: brew install fswatch"
        exit 1
    fi

    fswatch -0 --event Created --event Updated --event Renamed \
        "${QUEUE_DIR}/tasks/" "${QUEUE_DIR}/reports/" 2>/dev/null | \
    while read -d '' filepath; do
        process_event "$filepath"
    done
else
    # Linux: use inotifywait
    if ! command -v inotifywait &>/dev/null; then
        log "ERROR: inotifywait not found. Install: apt-get install inotify-tools"
        exit 1
    fi

    inotifywait -m -r -e create -e modify -e moved_to \
        "${QUEUE_DIR}/tasks/" "${QUEUE_DIR}/reports/" --format '%w%f' 2>/dev/null | \
    while read -r filepath; do
        process_event "$filepath"
    done
fi
