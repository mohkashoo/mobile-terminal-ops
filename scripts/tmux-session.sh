#!/usr/bin/env bash
# Launch or reattach a tmux workspace optimized for bug hunting
#
# Layout:
#   ┌──────────────────────────────────────┐
#   │  opencode session (pane 0)           │
#   │  ~/hunt/ workspace                   │
#   ├──────────────────┬───────────────────┤
#   │  Terminal (pane 1)│  Monitor (pane 2) │
#   │  tools, curl, etc│  htop / watch     │
#   └──────────────────┴───────────────────┘
#
# Usage:
#   bash tmux-session.sh                 # Create/attach hunt session
#   bash tmux-session.sh recon           # Create/attach named session
#   bash tmux-session.sh --notify        # With notification watcher
#   bash tmux-session.sh --notify recon  # Named session + watcher

set -euo pipefail

SESSION_NAME="hunt"
WORKSPACE_DIR="${HUNT_DIR:-$HOME/hunt}"
NOTIFY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --notify) NOTIFY=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--notify] [session-name]"
            exit 0 ;;
        *) SESSION_NAME="$1"; shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORKSPACE_DIR"

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    if [ "$NOTIFY" = true ]; then
        # Launch watcher in background
        bash "$SCRIPT_DIR/watch-session.sh" --target "${SESSION_NAME}:0.0" &
    fi
    exec tmux attach-session -t "$SESSION_NAME"
fi

tmux new-session -d -s "$SESSION_NAME" -c "$WORKSPACE_DIR" -n "hunt"

tmux rename-window -t "${SESSION_NAME}:0" "hunt"

tmux send-keys -t "${SESSION_NAME}:0" "cd $WORKSPACE_DIR" Enter
tmux send-keys -t "${SESSION_NAME}:0" "# opencode session ready" Enter

tmux split-window -h -t "${SESSION_NAME}:0" -c "$WORKSPACE_DIR"
tmux select-pane -t "${SESSION_NAME}:0.1"
tmux send-keys -t "${SESSION_NAME}:0.1" "cd $WORKSPACE_DIR" Enter
tmux send-keys -t "${SESSION_NAME}:0.1" "echo '=== Tool terminal ===' && ls" Enter

tmux split-window -v -t "${SESSION_NAME}:0.1" -c "$WORKSPACE_DIR"
tmux select-pane -t "${SESSION_NAME}:0.2"
tmux send-keys -t "${SESSION_NAME}:0.2" "htop" Enter

tmux select-pane -t "${SESSION_NAME}:0.0"

tmux set-option -t "$SESSION_NAME" status-left "#[fg=green]#S #[fg=cyan]| #{session_windows} windows"
tmux set-option -t "$SESSION_NAME" status-right "#[fg=yellow]%Y-%m-%d #[fg=cyan]%H:%M"

if [ "$NOTIFY" = true ]; then
    bash "$SCRIPT_DIR/watch-session.sh" --target "${SESSION_NAME}:0.0" &
fi

tmux attach-session -t "$SESSION_NAME"
