#!/data/data/com.termux/files/usr/bin/bash
# Quick-connect script for Termux -> Server
# Usage: ./connect.sh [tmux-session-name]
#
# Features:
#   - Auto-reconnect on network drop (3 retries)
#   - Reattaches to named tmux session
#   - Carries clipboard content from phone as stdin
#   - Logs connection attempts

set -euo pipefail

SESSION="${1:-hunt}"
MAX_RETRIES=3
RETRY_DELAY=3
LOG=~/hunt-connect.log

log()  { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
info() { echo -e "\033[0;36m[*]\033[0m $*"; }
err()  { echo -e "\033[0;31m[x]\033[0m $*"; }

log "Connecting to session=$SESSION"

if ! command -v termux-clipboard-get &>/dev/null; then
    CLIPBOARD=""
else
    CLIPBOARD=$(termux-clipboard-get 2>/dev/null || echo "")
    [ -n "$CLIPBOARD" ] && info "Clipboard: ${CLIPBOARD:0:60}..."
fi

for ((i=1; i<=MAX_RETRIES; i++)); do
    info "Connection attempt $i/$MAX_RETRIES..."

    if [ -n "$CLIPBOARD" ]; then
        echo "$CLIPBOARD" | ssh -t hunt "tmux new-session -A -s '$SESSION'"
    else
        ssh -t hunt "tmux new-session -A -s '$SESSION'"
    fi

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        log "Session ended cleanly (exit=0)"
        info "Session ended."
        exit 0
    elif [ $EXIT_CODE -eq 255 ]; then
        log "SSH connection failed (exit=255), attempt $i/$MAX_RETRIES"
        err "Connection lost. Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    else
        log "Session exited with code=$EXIT_CODE"
        info "Session exited (code=$EXIT_CODE)."
        exit $EXIT_CODE
    fi
done

err "Failed to connect after $MAX_RETRIES attempts."
log "Failed after $MAX_RETRIES attempts"
exit 1
