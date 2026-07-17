#!/usr/bin/env bash
# Watch a tmux pane and send notifications for interesting events.
# Launched by tmux-session.sh --notify (or run standalone).
#
# Usage:
#   bash watch-session.sh [--target hunt:0.0] [--config path/to/config]
#
# What it detects:
#   1. Stall — pane output hasn't changed for > STALL_TIMEOUT seconds
#   2. Session gone — tmux session/pane no longer exists
#   3. Keywords — new output matches alert patterns (e.g. "CRITICAL")

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"
CONFIG_PATH="${NOTIFY_CONFIG:-$PROJECT_DIR/config/notify-config}"

# ── Defaults ──────────────────────────────────
TMUX_TARGET="hunt:0.0"
POLL_INTERVAL=10
STALL_TIMEOUT=120
COOLDOWN=300
KEYWORDS=""

# ── Load config ───────────────────────────────
if [ -f "$CONFIG_PATH" ]; then
    . "$CONFIG_PATH"
fi

# Parse CLI args (override config)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TMUX_TARGET="$2"; shift 2 ;;
        --config) CONFIG_PATH="$2"; shift 2 ;;
        --poll) POLL_INTERVAL="$2"; shift 2 ;;
        --stall) STALL_TIMEOUT="$2"; shift 2 ;;
        --cool) COOLDOWN="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--target tmux_target] [--config path] [--poll N] [--stall N] [--cool N]"
            exit 0 ;;
        *) shift ;;
    esac
done

# If no config (and no NTFY_TOPIC), skip silently
if [ ! -f "$CONFIG_PATH" ] && [ -z "${NTFY_TOPIC:-}" ]; then
    exit 0
fi

# ── State tracking ────────────────────────────
LAST_OUTPUT=""
LAST_CHANGE_TS=$(date +%s)
LAST_ALERT_STALL=0
LAST_ALERT_KEYWORD=0
LAST_ALERT_GONE=0

alert() {
    local title="$1"
    local msg="$2"
    local pri="${3:-3}"
    bash "$NOTIFY_SCRIPT" "$title" "$msg" "$pri" 2>/dev/null || true
}

get_pane_output() {
    tmux capture-pane -t "$TMUX_TARGET" -p -S -50 2>/dev/null || echo ""
}

pane_exists() {
    tmux has-session -t "${TMUX_TARGET%:*}" 2>/dev/null && \
    tmux list-panes -t "${TMUX_TARGET%:*}" -F "#{pane_id}" 2>/dev/null | \
        grep -q ".${TMUX_TARGET##*:}" 2>/dev/null
    return $?
}

now() {
    date +%s
}

# ── Main loop ─────────────────────────────────
FIRST_RUN=true

while true; do
    if ! pane_exists; then
        if [ $(( $(now) - LAST_ALERT_GONE )) -gt "$COOLDOWN" ]; then
            alert "Session Ended" "tmux session $TMUX_TARGET is gone" 4
            LAST_ALERT_GONE=$(now)
        fi
        sleep "$POLL_INTERVAL"
        continue
    fi

    CURRENT_OUTPUT=$(get_pane_output)
    NOW=$(now)

    if [ "$FIRST_RUN" = true ]; then
        LAST_OUTPUT="$CURRENT_OUTPUT"
        LAST_CHANGE_TS=$NOW
        FIRST_RUN=false
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Check for output change
    if [ "$CURRENT_OUTPUT" != "$LAST_OUTPUT" ]; then
        LAST_OUTPUT="$CURRENT_OUTPUT"
        LAST_CHANGE_TS=$NOW

        # Check for keyword matches in new content
        if [ -n "$KEYWORDS" ]; then
            MATCHES=$(echo "$CURRENT_OUTPUT" | grep -iE "$KEYWORDS" 2>/dev/null || true)
            if [ -n "$MATCHES" ] && [ $(( NOW - LAST_ALERT_KEYWORD )) -gt "$COOLDOWN" ]; then
                FIRST_MATCH=$(echo "$MATCHES" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-120)
                alert "Keyword Match" "$FIRST_MATCH" 4
                LAST_ALERT_KEYWORD=$NOW
            fi
        fi
    else
        # Output unchanged — check for stall
        STALL_SECONDS=$(( NOW - LAST_CHANGE_TS ))
        if [ "$STALL_SECONDS" -ge "$STALL_TIMEOUT" ] && [ $(( NOW - LAST_ALERT_STALL )) -gt "$COOLDOWN" ]; then
            alert "Stalled" "No output for ${STALL_SECONDS}s in $TMUX_TARGET — waiting for input?" 3
            LAST_ALERT_STALL=$NOW
        fi
    fi

    sleep "$POLL_INTERVAL"
done
