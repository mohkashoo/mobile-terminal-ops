#!/data/data/com.termux/files/usr/bin/bash
# Quick-connect script for Termux -> Server
# Usage: ./connect.sh [tmux-session-name] [--timeout 10] [--clipboard]
#
# Features:
#   - Auto-reconnect on network drop (3 retries)
#   - Reattaches to named tmux session
#   - Carries clipboard content from phone as stdin (OPT-IN: --clipboard)
#   - Logs connection attempts

set -euo pipefail

SESSION="${1:-hunt}"
MAX_RETRIES=3
RETRY_DELAY=3
SSH_TIMEOUT=10
CARRY_CLIPBOARD=false
LOG=~/hunt-connect.log

log()  { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
info() { echo -e "\033[0;36m[*]\033[0m $*"; }
err()  { echo -e "\033[0;31m[x]\033[0m $*"; }

usage() {
    echo "Usage: $0 [session-name] [--timeout N] [--clipboard]"
    echo ""
    echo "Arguments:"
    echo "  session-name   tmux session to attach to (default: hunt)"
    echo "  --timeout N    SSH connection timeout in seconds (default: 10)"
    echo "  --clipboard    Also pipe the phone clipboard into the SSH session."
    echo "                 OPT-IN. Never copy passwords, tokens, or keys through"
    echo "                 clipboard sync — assume anything you copy can leak."
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) SSH_TIMEOUT="${2:-10}"; shift 2 ;;
        --clipboard) CARRY_CLIPBOARD=true; shift ;;
        --help|-h) usage ;;
        *) SESSION="$1"; shift ;;
    esac
done

log "Connecting to session=$SESSION timeout=${SSH_TIMEOUT}s clipboard=$CARRY_CLIPBOARD"

warn_carry() {
    echo -e "\033[0;33m[!]\033[0m Carrying clipboard content (${1:0:60}...)."
    echo -e "\033[0;33m[!]\033[0m Do NOT copy passwords, tokens, or keys through this."
}

CLIPBOARD=""
if [ "$CARRY_CLIPBOARD" = true ]; then
    if ! command -v termux-clipboard-get &>/dev/null; then
        err "termux-clipboard-get not found. Install termux-api to use --clipboard."
    else
        CLIPBOARD=$(termux-clipboard-get 2>/dev/null || echo "")
        [ -n "$CLIPBOARD" ] && warn_carry "$CLIPBOARD"
    fi
fi

for ((i=1; i<=MAX_RETRIES; i++)); do
    info "Connection attempt $i/$MAX_RETRIES..."

    if [ -n "$CLIPBOARD" ]; then
        echo "$CLIPBOARD" | ssh -o ConnectTimeout="$SSH_TIMEOUT" -t hunt \
            "tmux new-session -A -s '$SESSION'"
    else
        ssh -o ConnectTimeout="$SSH_TIMEOUT" -t hunt \
            "tmux new-session -A -s '$SESSION'"
    fi

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        log "Session ended cleanly (exit=0)"
        info "Session ended."
        exit 0
    elif [ $EXIT_CODE -eq 255 ]; then
        log "SSH connection failed (exit=255), attempt $i/$MAX_RETRIES"
        if [ $i -lt "$MAX_RETRIES" ]; then
            err "Connection lost. Retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
    else
        log "Session exited with code=$EXIT_CODE"
        info "Session exited (code=$EXIT_CODE)."
        exit $EXIT_CODE
    fi
done

err "Failed to connect after $MAX_RETRIES attempts."
log "Failed after $MAX_RETRIES attempts"
exit 1
