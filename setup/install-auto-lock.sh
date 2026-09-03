#!/usr/bin/env bash
# Install the dead-man's switch for the "phone lost/stolen" risk.
#
# What this does on the SERVER:
#   1. Writes ~/.ssh/rc so every Tailscale (phone) SSH login updates the
#      heartbeat automatically.
#   2. Installs scripts/auto-lock-server.sh to ~/.local/bin/mto-auto-lock.sh.
#   3. Schedules the check hourly — system-level systemd timer (Linux) so it
#      runs even with NO login session (unlike a user timer without linger),
#      or a crontab entry as fallback.
#
# When no heartbeat has arrived for MAX_IDLE_HOURS (default 24), the phone's
# key is revoked from ~/.ssh/authorized_keys automatically.
#
# Usage (run on the server):
#   bash setup/install-auto-lock.sh
#   MAX_IDLE_HOURS=12 bash setup/install-auto-lock.sh    # stricter
#   PHONE_KEY_COMMENT='my-phone-key' bash setup/install-auto-lock.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTO_LOCK="$SCRIPT_DIR/scripts/auto-lock-server.sh"
BIN_DIR="$HOME/.local/bin"
HEARTBEAT_FILE="$HOME/.phone-heartbeat"
MAX_IDLE_HOURS="${MAX_IDLE_HOURS:-24}"

mkdir -p "$BIN_DIR"
mkdir -p "$(dirname "$HEARTBEAT_FILE")"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# ── 1. Heartbeat on login via ~/.ssh/rc ──────
info "Writing ~/.ssh/rc to update heartbeat on every Tailscale SSH login..."
if [ -f "$HOME/.ssh/rc" ]; then
    warn "~/.ssh/rc already exists — backing it up."
    cp "$HOME/.ssh/rc" "$HOME/.ssh/rc.bak.$(date +%Y%m%d-%H%M%S)"
fi
cat > "$HOME/.ssh/rc" << RC
# mobile-terminal-ops heartbeat: updated on every Tailscale SSH login.
# Removes this line to disable the dead-man's switch.
if [ -n "\${SSH_CLIENT:-}" ]; then
    case "\${SSH_CLIENT%% *}" in
        100.*) touch "$HEARTBEAT_FILE" ;;
    esac
fi
RC
chmod 700 "$HOME/.ssh/rc"
ok "Heartbeat installed — every phone (Tailscale) login refreshes $HEARTBEAT_FILE"
warn "FIRST-RUN FOOTGUN: the switch is now armed. If the phone does NOT log in within"
warn "MAX_IDLE_HOURS ($MAX_IDLE_HOURS h), the key gets revoked. Log in once to arm it safely."

# ── 2. Install the check script ───────────────
info "Installing $AUTO_LOCK → $BIN_DIR/mto-auto-lock.sh"
cp "$AUTO_LOCK" "$BIN_DIR/mto-auto-lock.sh"
chmod +x "$BIN_DIR/mto-auto-lock.sh"
ok "Installed."

# ── 3. Scheduling ─────────────────────────────
SCHEDULED=false

if [ "$(uname -s)" = "Linux" ] && command -v systemctl >/dev/null 2>&1; then
    info "Installing SYSTEM-level systemd timer (runs hourly, no login session needed)..."
    # System-level units run regardless of the user's login state; they are
    # the only form that doesn't silently die when you reboot and haven't
    # logged in yet. Requires sudo.
    sudo tee /etc/systemd/system/mto-autolock.service > /dev/null << EOF
[Unit]
Description=Mobile Terminal Ops — revoke phone key after idle timeout

[Service]
Type=oneshot
User=$USER
ExecStart=$BIN_DIR/mto-auto-lock.sh
Environment=MAX_IDLE_HOURS=$MAX_IDLE_HOURS
EOF
    sudo tee /etc/systemd/system/mto-autolock.timer > /dev/null << EOF
[Unit]
Description=Mobile Terminal Ops — dead-man's switch hourly check

[Timer]
OnBootSec=15min
OnUnitActiveSec=1h
Unit=mto-autolock.service

[Install]
WantedBy=timers.target
EOF
    if sudo systemctl daemon-reload && sudo systemctl enable --now mto-autolock.timer; then
        ok "systemd timer enabled (mto-autolock.timer, hourly)."
        SCHEDULED=true
    else
        err "systemd timer install failed — falling back to cron."
    fi
fi

if [ "$SCHEDULED" = false ] && command -v crontab >/dev/null 2>&1; then
    info "Installing crontab entry (hourly)."
    CRON_LINE="0 * * * * $BIN_DIR/mto-auto-lock.sh"
    # `|| true` on `crontab -l` so a fresh system (no crontab yet) still gets
    # the entry written instead of aborting on the non-zero exit.
    ( crontab -l 2>/dev/null | grep -v 'mto-auto-lock.sh' || true; echo "$CRON_LINE" ) | crontab -
    ok "Crontab entry installed: $CRON_LINE"
    SCHEDULED=true
fi

if [ "$SCHEDULED" = false ]; then
    err "No scheduler installed! Add a crontab line manually:"
    err "  $BIN_DIR/mto-auto-lock.sh"
    err "The dead-man's switch is NOT armed."
    exit 1
fi

echo ""
ok "=== Dead-man's switch installed ==="
echo ""
info "Phone heartbeats arrive automatically on every SSH login."
info "If no heartbeat for ${MAX_IDLE_HOURS}h, the phone key is revoked."
info ""
info "How to NOTICE if the watchdog dies (README 'Watchdog health'):"
info "  ${BIN_DIR}/mto-auto-lock.sh --check-health"
info ""
info "Tuning (install-time env vars):"
info "  MAX_IDLE_HOURS   (default 24)"
info "  PHONE_KEY_COMMENT (default termux-|iphone-|blink)"
info ""
info "Log file:      ${XDG_DATA_HOME:-$HOME/.local/share}/mobile-terminal-ops/auto-lock.log"
info "Last run:      ${XDG_DATA_HOME:-$HOME/.local/share}/mobile-terminal-ops/auto-lock-last-run"