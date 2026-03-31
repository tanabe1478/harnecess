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
PIPELINE_FILE="${SCRIPT_DIR}/pipeline/default.yaml"
INBOX_WRITE="${SCRIPT_DIR}/scripts/inbox_write.sh"
PYTHON="$PYTHON"

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

# Validate state transition against pipeline definition
validate_transition() {
    local from_state="$1"
    local to_state="$2"

    if [ ! -f "$PIPELINE_FILE" ]; then
        log "WARNING: Pipeline file not found, skipping validation"
        return 0
    fi

    "$PYTHON" -c "
import yaml, sys

with open('${PIPELINE_FILE}') as f:
    pipeline = yaml.safe_load(f)

from_state = '${from_state}'
to_state = '${to_state}'

# Find current state in pipeline
for state in pipeline.get('states', []):
    if state['name'] == from_state:
        valid_targets = [t['to'] for t in state.get('transitions', [])]
        if to_state in valid_targets:
            sys.exit(0)  # Valid
        else:
            print(f'INVALID: {from_state} → {to_state}. Valid: {valid_targets}', file=sys.stderr)
            sys.exit(1)  # Invalid

# from_state not found (e.g., idle, initial)
sys.exit(0)
" 2>&1
}

# Check timeouts for current state
check_timeout() {
    if [ ! -f "$STATE_FILE" ] || [ ! -f "$PIPELINE_FILE" ]; then
        return
    fi

    "$PYTHON" -c "
import yaml, sys
from datetime import datetime, timezone

with open('${STATE_FILE}') as f:
    state = yaml.safe_load(f) or {}

with open('${PIPELINE_FILE}') as f:
    pipeline = yaml.safe_load(f)

current = state.get('current_state', 'idle')
timestamp_str = state.get('timestamp', '')
if not timestamp_str:
    sys.exit(0)

# Find timeout for current state
timeout_sec = 0
for s in pipeline.get('states', []):
    if s['name'] == current:
        timeout_sec = s.get('timeout_seconds', 0)
        break

if timeout_sec <= 0:
    sys.exit(0)

try:
    ts = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
    elapsed = (datetime.now(timezone.utc) - ts).total_seconds()
    if elapsed > timeout_sec:
        remaining = int(elapsed - timeout_sec)
        print(f'TIMEOUT:{current}:{int(elapsed)}:{timeout_sec}')
except:
    pass
" 2>/dev/null
}

# Update state.yaml
update_state() {
    local new_state="$1"
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local current_state=""
    if [ -f "$STATE_FILE" ]; then
        current_state="$("$PYTHON" -c "
import yaml
with open('${STATE_FILE}') as f:
    d = yaml.safe_load(f) or {}
print(d.get('current_state', ''))
" 2>/dev/null || echo "")"
    fi

    # Validate transition
    if [ -n "$current_state" ]; then
        local validation
        validation="$(validate_transition "$current_state" "$new_state" 2>&1 || true)"
        if echo "$validation" | grep -q "INVALID"; then
            log "BLOCKED: $validation"
            return 1
        fi
    fi

    "$PYTHON" -c "
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
        status="$("$PYTHON" -c "
import yaml
with open('${filepath}') as f:
    d = yaml.safe_load(f) or {}
task = d.get('task', d)
print(task.get('status', ''))
" 2>/dev/null || echo "")"

        if [ "$status" = "assigned" ]; then
            local task_id
            task_id="$("$PYTHON" -c "
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

# Background timeout checker (runs every 30 seconds)
(
    while true; do
        sleep 30
        timeout_result="$(check_timeout)"
        if [ -n "$timeout_result" ]; then
            IFS=':' read -r _ state elapsed timeout_sec <<< "$timeout_result"
            log "TIMEOUT: ${state} has been active for ${elapsed}s (limit: ${timeout_sec}s)"
            notify_agent "lead" "TIMEOUT: ${state} が ${elapsed} 秒経過（制限: ${timeout_sec}秒）。csm でエージェントの状態を確認してください。"
        fi
    done
) &
TIMEOUT_PID=$!
trap "kill $TIMEOUT_PID 2>/dev/null" EXIT

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
