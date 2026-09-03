#!/data/data/com.termux/files/usr/bin/bash
# Phone-side heartbeat for the server's dead-man's switch.
#
# Every SSH login from the phone already updates the heartbeat automatically
# via ~/.ssh/rc on the server (installed by setup/install-auto-lock.sh). This
# script is a manual helper if you want to poke the heartbeat WITHOUT logging
# in (e.g. you're in a safe spot and don't want the auto-lock to fire).
#
# Usage:
#   bash heartbeat.sh              # touch the server-side heartbeat
#   bash heartbeat.sh --check      # show when the last heartbeat was

set -euo pipefail

REMOTE_HOST="${1:-hunt}"

case "${1:-}" in
    --check)
        ssh "$REMOTE_HOST" "stat -c '%y  (age: %y)' ~/.phone-heartbeat 2>/dev/null || echo 'no heartbeat yet'"
        ;;
    --help|-h)
        echo "Usage: $0 [--check]"
        exit 0
        ;;
    *)
        ssh "$REMOTE_HOST" "touch ~/.phone-heartbeat && stat -c 'heartbeat updated: %y' ~/.phone-heartbeat"
        ;;
esac