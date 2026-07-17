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
#
# Config is read from (first found wins):
#   $NOTIFY_CONFIG env var
#   ../config/notify-config (relative to this script)
#   $XDG_CONFIG_HOME/mobile-terminal-ops/notify-config

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"
LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mobile-terminal-ops"
LOG_FILE="$LOG_DIR/watch-session.log"
PID_FILE="$LOG_DIR/watch-session.pid"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# ── Defaults ──────────────────────────────────
TMUX_TARGET="hunt:0.0"
POLL_INTERVAL=10
STALL_TIMEOUT=120
COOLDOWN=300
KEYWORDS=""

# ── Load config ───────────────────────────────
# Priority: env var > project dir > xdg config
CONFIG_PATH="${NOTIFY_CONFIG:-}"

if [ -z "$CONFIG_PATH" ]; then
    if [ -f "$PROJECT_DIR/config/notify-config" ]; then
        CONFIG_PATH="$PROJECT_DIR/config/notify-config"
    elif [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/mobile-terminal-ops/notify-config" ]; then
        CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/mobile-terminal-ops/notify-config"
    fi
fi

if [ -n "$CONFIG_PATH" ] && [ -f "$CONFIG_PATH" ]; then
    . "$CONFIG_PATH"
    log "Loaded config: $CONFIG_PATH"
fi

# Parse CLI args (override config)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TMUX_TARGET="$2"; shift 2 ;;
        --config) CONFIG_PATH="$2"; shift 2 ;;
        --poll) POLL_INTERVAL="$2"; shift 2 ;;
        --stall) STALL_TIMEOUT="$2"; shift 2 ;;
        --cool) COOLDOWN="$2"; shift 2 ;;
        --verbose) set -x; shift ;;
        --help|-h)
            echo "Usage: $0 [--target tmux:win.pane] [--config path] [--poll N] [--stall N] [--cool N]"
            exit 0 ;;
        *) shift ;;
    esac
done

# If no NTFY_TOPIC or PUSHOVER set, skip silently (opt-in feature)
NTFY_TOPIC="${NTFY_TOPIC:-}"
PUSHOVER_USER="${PUSHOVER_USER:-}"
PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-}"

if [ -z "$NTFY_TOPIC" ] && [ -z "$PUSHOVER_USER" ]; then
    log "No notification backend configured. Skipping."
    exit 0
fi

# ── Single-instance guard ─────────────────────
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log "Killing old watcher (PID $OLD_PID)"
        kill "$OLD_PID" 2>/dev/null || true
        sleep 1
    fi
fi
echo "$$" > "$PID_FILE"

log "Starting watcher for $TMUX_TARGET (poll=${POLL_INTERVAL}s, stall=${STALL_TIMEOUT}s)"
log "Notifying via: ntfy.sh/$NTFY_TOPIC"

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
    log "ALERT: $title — $msg (pri=$pri)"
    bash "$NOTIFY_SCRIPT" "$title" "$msg" "$pri" 2>/dev/null || true
}

get_pane_output() {
    tmux capture-pane -t "$TMUX_TARGET" -p -S -50 2>/dev/null || echo ""
}

pane_exists() {
    local session="${TMUX_TARGET%%:*}"
    local pane="${TMUX_TARGET##*.}"
    tmux has-session -t "$session" 2>/dev/null && \
    tmux list-panes -t "$session" -F "#{pane_index}" 2>/dev/null | \
        grep -qx "$pane" 2>/dev/null
}

now() {
    date +%s
}

# ── Main loop ─────────────────────────────────
FIRST_RUN=true
log "Watcher started (PID $$)"

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
        log "First run — captured initial pane state (${#CURRENT_OUTPUT} chars)"
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
                log "Keyword triggered: $FIRST_MATCH"
                alert "Keyword Match" "$FIRST_MATCH" 4
                LAST_ALERT_KEYWORD=$NOW
            fi
        fi
    else
        # Output unchanged — check for stall
        STALL_SECONDS=$(( NOW - LAST_CHANGE_TS ))
        if [ "$STALL_SECONDS" -ge "$STALL_TIMEOUT" ] && [ $(( NOW - LAST_ALERT_STALL )) -gt "$COOLDOWN" ]; then
            log "Stall detected: ${STALL_SECONDS}s"
            alert "Stalled" "No output for ${STALL_SECONDS}s in $TMUX_TARGET — waiting for input?" 3
            LAST_ALERT_STALL=$NOW
        fi
    fi

    sleep "$POLL_INTERVAL"
done
