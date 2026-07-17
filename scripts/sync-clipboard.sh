#!/data/data/com.termux/files/usr/bin/bash
# Bidirectional clipboard sync between Termux and remote server
#
# This script watches ~/.phone-clipboard on the server for changes.
# When a new line appears, it syncs back to the Termux clipboard.
# Also pushes Termux clipboard content to the server on demand.
#
# Usage:
#   bash sync-clipboard.sh watch       # Start clipboard watch daemon
#   bash sync-clipboard.sh push        # Push phone clipboard → server
#   bash sync-clipboard.sh pull        # Pull server file → phone clipboard

set -euo pipefail

REMOTE_HOST="hunt"
REMOTE_FILE="~/.phone-clipboard"
SYNC_LOG=~/clipboard-sync.log

info() { echo -e "\033[0;36m[*]\033[0m $*"; }
ok()   { echo -e "\033[0;32m[+]\033[0m $*"; }

push_to_server() {
    if ! command -v termux-clipboard-get &>/dev/null; then
        echo "termux-clipboard-get not found. Install termux-api."
        exit 1
    fi
    local clip
    clip=$(termux-clipboard-get 2>/dev/null || echo "")
    if [ -z "$clip" ]; then
        echo "Clipboard is empty."
        return
    fi
    echo "$clip" | ssh "$REMOTE_HOST" "cat > '$REMOTE_FILE'"
    echo "[$(date)] Pushed: ${clip:0:80}..." >> "$SYNC_LOG"
    ok "Pushed to server: ${clip:0:80}..."
}

pull_from_server() {
    local content
    content=$(ssh "$REMOTE_HOST" "cat '$REMOTE_FILE' 2>/dev/null" || echo "")
    if [ -z "$content" ]; then
        echo "Remote clipboard file is empty."
        return
    fi
    echo "$content" | termux-clipboard-set
    echo "[$(date)] Pulled: ${content:0:80}..." >> "$SYNC_LOG"
    ok "Pulled to phone: ${content:0:80}..."
}

watch_server() {
    info "Watching $REMOTE_HOST:$REMOTE_FILE for changes..."
    info "Ctrl+C to stop."
    local last_checksum=""

    while true; do
        local current
        current=$(ssh "$REMOTE_HOST" "md5sum '$REMOTE_FILE' 2>/dev/null | cut -d' ' -f1" || echo "")
        if [ -n "$current" ] && [ "$current" != "$last_checksum" ]; then
            last_checksum="$current"
            pull_from_server
        fi
        sleep 2
    done
}

case "${1:-}" in
    push)
        push_to_server
        ;;
    pull)
        pull_from_server
        ;;
    watch)
        watch_server
        ;;
    *)
        echo "Usage: $0 {push|pull|watch}"
        echo "  push   — Push phone clipboard to server"
        echo "  pull   — Pull server clipboard to phone"
        echo "  watch  — Watch server clipboard file for changes (poll)"
        exit 1
        ;;
esac
