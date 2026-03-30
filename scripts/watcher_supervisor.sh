#!/usr/bin/env bash
set -euo pipefail

# Keep inbox watchers alive in a persistent tmux-hosted shell.
# This script is designed to run forever.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

mkdir -p logs queue/inbox

ensure_inbox_file() {
    local agent="$1"
    if [ ! -f "queue/inbox/${agent}.yaml" ]; then
        printf 'messages: []\n' > "queue/inbox/${agent}.yaml"
    fi
}

pane_exists() {
    local pane="$1"
    tmux list-panes -a -F "#{session_name}:#{window_name}.#{pane_index}" 2>/dev/null | grep -qx "$pane"
}

start_watcher_if_missing() {
    local agent="$1"
    local pane="$2"
    local log_file="$3"
    local cli

    ensure_inbox_file "$agent"
    if ! pane_exists "$pane"; then
        return 0
    fi

    if pgrep -f "scripts/inbox_watcher.sh ${agent} " >/dev/null 2>&1; then
        return 0
    fi

    cli=$(tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null || echo "claude")
    nohup bash scripts/inbox_watcher.sh "$agent" "$pane" "$cli" >> "$log_file" 2>&1 &
}

while true; do
    start_watcher_if_missing "lead" "harnecess:main.0" "logs/inbox_watcher_lead.log"
    start_watcher_if_missing "planner" "harnecess-agents:agents.0" "logs/inbox_watcher_planner.log"
    start_watcher_if_missing "builder" "harnecess-agents:agents.1" "logs/inbox_watcher_builder.log"
    start_watcher_if_missing "checker" "harnecess-agents:agents.2" "logs/inbox_watcher_checker.log"
    start_watcher_if_missing "writer" "harnecess-agents:agents.3" "logs/inbox_watcher_writer.log"
    sleep 5
done
