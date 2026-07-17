#!/usr/bin/env bash
# Notification sender — sends alerts via ntfy.sh (default) or Pushover.
#
# Usage:
#   bash notify.sh "title" "message" [priority]
#
# Priority levels (ntfy): 1=min, 2=low, 3=default, 4=high, 5=emergency
# Priority levels (Pushover): -1=low, 0=normal, 1=high, 2=emergency
#
# Reads config from:
#   ~/.config/mobile-terminal-ops/notify-config
#   or ../config/notify-config (relative to this script)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="${NOTIFY_CONFIG:-$PROJECT_DIR/config/notify-config}"
CONFIG_XDG="${XDG_CONFIG_HOME:-$HOME/.config}/mobile-terminal-ops/notify-config"

# Look for config in multiple locations
load_config() {
    if [ -f "$CONFIG_PATH" ]; then
        . "$CONFIG_PATH"
        return 0
    fi
    if [ -f "$CONFIG_XDG" ]; then
        . "$CONFIG_XDG"
        return 0
    fi
    # Check current dir relative to where script is called from
    if [ -f "./config/notify-config" ]; then
        . "./config/notify-config"
        return 0
    fi
    return 1
}

if ! load_config; then
    # Silent skip — not configured means opt-out
    exit 0
fi

# Require at least a title and message
TITLE="${1:-}"
MESSAGE="${2:-}"
PRIORITY="${3:-3}"

if [ -z "$TITLE" ] || [ -z "$MESSAGE" ]; then
    echo "Usage: $0 <title> <message> [priority]" >&2
    exit 1
fi

send_ntfy() {
    local tags=""
    case "$PRIORITY" in
        1|2) tags=":warning:" ;;
        3)   tags=":bell:" ;;
        4|5) tags=":fire:" ;;
    esac

    curl -s -o /dev/null \
        -H "Title: $TITLE" \
        -H "Priority: $PRIORITY" \
        -H "Tags: $tags" \
        -d "$MESSAGE" \
        "https://ntfy.sh/${NTFY_TOPIC}"
}

send_pushover() {
    [ -z "${PUSHOVER_USER:-}" ] && return 1
    [ -z "${PUSHOVER_TOKEN:-}" ] && return 1

    local po_priority=0
    case "$PRIORITY" in
        1|2) po_priority=-1 ;;
        3)   po_priority=0 ;;
        4)   po_priority=1 ;;
        5)   po_priority=2 ;;
    esac

    curl -s -o /dev/null \
        -F "token=$PUSHOVER_TOKEN" \
        -F "user=$PUSHOVER_USER" \
        -F "title=$TITLE" \
        -F "message=$MESSAGE" \
        -F "priority=$po_priority" \
        "https://api.pushover.net/1/messages.json"
}

if [ -n "${PUSHOVER_USER:-}" ] && [ -n "${PUSHOVER_TOKEN:-}" ]; then
    send_pushover
elif [ -n "${NTFY_TOPIC:-}" ]; then
    send_ntfy
fi
