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

# Detect the SERVER OS (not the phone's) so the stat syntax matches.
server_os() {
    ssh "$REMOTE_HOST" "uname -s" 2>/dev/null || echo "unknown"
}

show_heartbeat() {
    case "$(server_os)" in
        Linux) ssh "$REMOTE_HOST" "stat -c '%y' ~/.phone-heartbeat 2>/dev/null || echo 'no heartbeat yet'" ;;
        *)     ssh "$REMOTE_HOST" "stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' ~/.phone-heartbeat 2>/dev/null || echo 'no heartbeat yet'" ;;
    esac
}

update_heartbeat() {
    case "$(server_os)" in
        Linux) ssh "$REMOTE_HOST" "touch ~/.phone-heartbeat && stat -c 'heartbeat updated: %y' ~/.phone-heartbeat" ;;
        *)     ssh "$REMOTE_HOST" "touch ~/.phone-heartbeat && stat -f 'heartbeat updated: %Sm' -t '%Y-%m-%d %H:%M:%S' ~/.phone-heartbeat" ;;
    esac
}

case "${1:-}" in
    --check) show_heartbeat ;;
    --help|-h)
        echo "Usage: $0 [--check]"
        exit 0
        ;;
    *) update_heartbeat ;;
esac