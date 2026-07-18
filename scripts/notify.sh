#!/usr/bin/env bash
# Notification sender — sends alerts via Telegram, Pushover, or ntfy.sh.
#
# Usage:
#   bash notify.sh "title" "message" [priority]
#   bash notify.sh --telegram-bot TOKEN --telegram-chat CHAT "title" "msg" 4
#   bash notify.sh --topic mytopic "title" "message" 4
#   bash notify.sh --pushover-user U --pushover-token T "title" "msg"
#
# Reads config from config/notify-config by default.
# CLI flags override config file values.
# Backend priority: Telegram > Pushover > ntfy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="${NOTIFY_CONFIG:-$PROJECT_DIR/config/notify-config}"

PRIORITY=3

# ── Parse CLI flags ───────────────────────────
CLI_TG_BOT=""
CLI_TG_CHAT=""
CLI_NTFY_TOPIC=""
CLI_PUSHOVER_USER=""
CLI_PUSHOVER_TOKEN=""

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --telegram-bot)  CLI_TG_BOT="$2";  shift 2 ;;
        --telegram-chat) CLI_TG_CHAT="$2"; shift 2 ;;
        --topic)         CLI_NTFY_TOPIC="$2"; shift 2 ;;
        --pushover-user) CLI_PUSHOVER_USER="$2"; shift 2 ;;
        --pushover-token) CLI_PUSHOVER_TOKEN="$2"; shift 2 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

TITLE="${POSITIONAL[0]:-}"
MESSAGE="${POSITIONAL[1]:-}"
PRIORITY="${POSITIONAL[2]:-3}"

if [ -z "$TITLE" ] || [ -z "$MESSAGE" ]; then
    echo "Usage: $0 [--telegram-bot TOKEN --telegram-chat ID] [--topic name] [--pushover-user U --pushover-token T] <title> <message> [priority]" >&2
    echo "" >&2
    echo "  Priority: 1=min, 2=low, 3=default, 4=high, 5=emergency" >&2
    exit 1
fi

# ── Load config file ──────────────────────────
TG_BOT=""
TG_CHAT=""
NTFY_TOPIC=""
PUSHOVER_USER=""
PUSHOVER_TOKEN=""

if [ -f "$CONFIG_PATH" ]; then
    . "$CONFIG_PATH"
fi

# CLI overrides config
[ -n "$CLI_TG_BOT" ]         && TG_BOT="$CLI_TG_BOT"
[ -n "$CLI_TG_CHAT" ]        && TG_CHAT="$CLI_TG_CHAT"
[ -n "$CLI_NTFY_TOPIC" ]     && NTFY_TOPIC="$CLI_NTFY_TOPIC"
[ -n "$CLI_PUSHOVER_USER" ]  && PUSHOVER_USER="$CLI_PUSHOVER_USER"
[ -n "$CLI_PUSHOVER_TOKEN" ] && PUSHOVER_TOKEN="$CLI_PUSHOVER_TOKEN"

if [ -z "$TG_BOT$TG_CHAT$NTFY_TOPIC$PUSHOVER_USER" ]; then
    echo "No notification backend configured." >&2
    echo "Set one in config/notify-config or pass a flag:" >&2
    echo "  --telegram-bot TOKEN --telegram-chat ID" >&2
    echo "  --topic NTFY_TOPIC" >&2
    echo "  --pushover-user USER --pushover-token TOKEN" >&2
    exit 1
fi

# ── Priority emoji ────────────────────────────
priority_emoji() {
    case "$1" in
        1|2) echo "🤔" ;;
        3)   echo "ℹ️" ;;
        4)   echo "⚠️" ;;
        5)   echo "🚨" ;;
    esac
}

# ── Senders ───────────────────────────────────
send_telegram() {
    local icon
    icon=$(priority_emoji "$PRIORITY")
    local text="${icon} *${TITLE}*%0A%0A${MESSAGE}"

    curl -s -o /dev/null \
        "https://api.telegram.org/bot${TG_BOT}/sendMessage" \
        -d "chat_id=${TG_CHAT}&text=${text}&parse_mode=Markdown&disable_web_page_preview=true"
    echo "Telegram alert sent"
}

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
    echo "ntfy alert sent (topic: $NTFY_TOPIC)"
}

send_pushover() {
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
    echo "Pushover alert sent"
}

if [ -n "$TG_BOT" ] && [ -n "$TG_CHAT" ]; then
    send_telegram
elif [ -n "$PUSHOVER_USER" ] && [ -n "$PUSHOVER_TOKEN" ]; then
    send_pushover
elif [ -n "$NTFY_TOPIC" ]; then
    send_ntfy
fi
