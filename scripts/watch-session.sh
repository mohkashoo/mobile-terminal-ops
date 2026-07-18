#!/usr/bin/env bash
# Watch a tmux pane and send email summaries for every opencode response.
# Launched by tmux-session.sh --notify (or run standalone).
#
# Usage:
#   bash watch-session.sh --target /hunt/paypal:0.0
#
# For every output change in the pane, it calls email-summary.sh which
# sends a styled HTML email with the response content.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EMAIL_SCRIPT="$SCRIPT_DIR/email-summary.sh"
LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mobile-terminal-ops"
LOG_FILE="$LOG_DIR/watch-session.log"
PID_FILE="$LOG_DIR/watch-session.pid"
STATE_FILE="$LOG_DIR/pane-state.txt"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# ── Defaults ──────────────────────────────────
TMUX_TARGET="hunt:0.0"
POLL_INTERVAL=10
STALL_TIMEOUT=120
OUTPUT_COOLDOWN=15

# ── Load email config ────────────────────────
CONFIG_PATH="${EMAIL_CONFIG:-}"

if [ -z "$CONFIG_PATH" ]; then
    if [ -f "$PROJECT_DIR/config/email-config" ]; then
        CONFIG_PATH="$PROJECT_DIR/config/email-config"
    elif [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/mobile-terminal-ops/email-config" ]; then
        CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/mobile-terminal-ops/email-config"
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
        --cool) OUTPUT_COOLDOWN="$2"; shift 2 ;;
        --verbose) set -x; shift ;;
        --help|-h)
            echo "Usage: $0 [--target tmux:win.pane] [--config path] [--poll N] [--stall N] [--cool N]"
            exit 0 ;;
        *) shift ;;
    esac
done

if [ -z "${EMAIL_TO:-}" ]; then
    log "EMAIL_TO not configured. Skipping."
    exit 0
fi

log "Starting watcher for $TMUX_TARGET → email to $EMAIL_TO"

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
trap 'rm -f "$PID_FILE"; log "Watcher stopped (PID $$)"' EXIT

# ── State tracking ────────────────────────────
LAST_OUTPUT=""
LAST_CHANGE_TS=$(date +%s)
LAST_ALERT_STALL=0
LAST_ALERT_GONE=0
LAST_ALERT_EMAIL=0

get_pane_output() {
    tmux capture-pane -t "$TMUX_TARGET" -p -S -50 2>/dev/null || echo ""
}

pane_exists() {
    local session="${TMUX_TARGET%%:*}"
    local pane="${TMUX_TARGET##*.}"
    tmux has-session -t "$session" 2>/dev/null || return 1
    tmux list-panes -t "$session" -F "#{pane_index}" 2>/dev/null | grep -qx "$pane" 2>/dev/null || return 1
    return 0
}

now() {
    date +%s
}

send_email_summary() {
    local output="$1"
    local event_type="$2"
    local subject_prefix=""
    case "$event_type" in
        output)   subject_prefix="🔍 Opencode Response" ;;
        stall)    subject_prefix="⏳ Session Stalled" ;;
        ended)    subject_prefix="🚨 Session Ended" ;;
        started)  subject_prefix="🤖 Watcher Started" ;;
    esac
    log "Sending email: $subject_prefix (${#output} chars)"
    echo "$output" | bash "$EMAIL_SCRIPT" \
        --to "$EMAIL_TO" \
        --subject "$subject_prefix" \
        --source "$TMUX_TARGET" \
        2>/dev/null || log "Email send failed"
}

# ── Main loop ─────────────────────────────────
FIRST_RUN=true
log "Watcher started (PID $$)"

while true; do
    if ! pane_exists; then
        if [ $(( $(now) - LAST_ALERT_GONE )) -gt "$OUTPUT_COOLDOWN" ]; then
            send_email_summary "tmux session $TMUX_TARGET is gone" "ended"
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
        echo "$CURRENT_OUTPUT" > "$STATE_FILE"
        log "First run — captured initial pane state (${#CURRENT_OUTPUT} chars)"
        FIRST_RUN=false
        send_email_summary "Monitoring $TMUX_TARGET — every opencode response will be emailed here." "started"
        sleep "$POLL_INTERVAL"
        continue
    fi

    # ── Output changed? ─────────────────────
    if [ "$CURRENT_OUTPUT" != "$LAST_OUTPUT" ]; then
        LAST_OUTPUT="$CURRENT_OUTPUT"
        LAST_CHANGE_TS=$NOW
        echo "$CURRENT_OUTPUT" > "$STATE_FILE"

        # Send email with the new output (debounced)
        if [ $(( NOW - LAST_ALERT_EMAIL )) -gt "$OUTPUT_COOLDOWN" ]; then
            MESSAGE=$(echo "$CURRENT_OUTPUT" | head -30)
            send_email_summary "$MESSAGE" "output"
            LAST_ALERT_EMAIL=$NOW
        fi
    else
        # ── Output unchanged — check for stall ──
        STALL_SECONDS=$(( NOW - LAST_CHANGE_TS ))
        if [ "$STALL_SECONDS" -ge "$STALL_TIMEOUT" ] && [ $(( NOW - LAST_ALERT_STALL )) -gt "$OUTPUT_COOLDOWN" ]; then
            log "Stall detected: ${STALL_SECONDS}s"
            send_email_summary "No output for ${STALL_SECONDS}s — opencode is waiting for input." "stall"
            LAST_ALERT_STALL=$NOW
        fi
    fi

    sleep "$POLL_INTERVAL"
done
