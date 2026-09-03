#!/usr/bin/env bash
# Install the dead-man's switch for the "phone lost/stolen" risk.
#
# What this does on the SERVER:
#   1. Writes ~/.ssh/rc so every Tailscale (phone) SSH login updates the
#      heartbeat automatically.
#   2. Installs scripts/auto-lock-server.sh to ~/.local/bin/mto-auto-lock.sh.
#   3. Installs a systemd timer (Linux) — or a crontab entry (fallback) —
#      that runs the check hourly.
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

# ── 2. Install the check script ───────────────
info "Installing $AUTO_LOCK → $BIN_DIR/mto-auto-lock.sh"
cp "$AUTO_LOCK" "$BIN_DIR/mto-auto-lock.sh"
chmod +x "$BIN_DIR/mto-auto-lock.sh"
ok "Installed."

# ── 3. Scheduling: systemd timer or cron ──────
if [ "$(uname -s)" = "Linux" ] && command -v systemctl >/dev/null 2>&1; then
    info "Installing systemd timer (runs hourly)..."
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/mto-autolock.service" << EOF
[Unit]
Description=Mobile Terminal Ops — revoke phone key after idle timeout

[Service]
Type=oneshot
ExecStart=$BIN_DIR/mto-auto-lock.sh
Environment=MAX_IDLE_HOURS=$MAX_IDLE_HOURS
EOF
    cat > "$HOME/.config/systemd/user/mto-autolock.timer" << EOF
[Unit]
Description=Mobile Terminal Ops — dead-man's switch hourly check

[Timer]
OnBootSec=15min
OnUnitActiveSec=1h
Unit=mto-autolock.service

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now mto-autolock.timer
    ok "systemd user timer enabled (mto-autolock.timer, hourly)."
    systemctl --user list-timers mto-autolock.timer 2>/dev/null | grep mto || true
else
    info "No systemd available — installing crontab entry (hourly)."
    CRON_LINE="0 * * * * $BIN_DIR/mto-auto-lock.sh"
    ( crontab -l 2>/dev/null | grep -v 'mto-auto-lock.sh'; echo "$CRON_LINE" ) | crontab -
    ok "Crontab entry installed: $CRON_LINE"
fi

echo ""
ok "=== Dead-man's switch installed ==="
echo ""
info "Phone heartbeats arrive automatically on every SSH login."
info "If no heartbeat for ${MAX_IDLE_HOURS}h, the phone key is revoked."
info ""
info "Tuning:"
info "  MAX_IDLE_HOURS env var at install time (default 24)"
info "  PHONE_KEY_COMMENT env var at install time to match your phone key"
info ""
info "Manual check:  $BIN_DIR/mto-auto-lock.sh"
info "Log file:      ${XDG_DATA_HOME:-$HOME/.local/share}/mobile-terminal-ops/auto-lock.log"