#!/usr/bin/env bash
# Dead-man's switch for the "phone lost/stolen" risk.
#
# If the phone hasn't sent a heartbeat in MAX_IDLE_HOURS, this script:
#   1. Removes the phone's key from ~/.ssh/authorized_keys (no more logins)
#   2. Optionally kills open SSH sessions (KILL_SESSIONS=true)
#
# Heartbeats are written automatically on every Tailscale SSH login via
# ~/.ssh/rc (see setup/install-auto-lock.sh). Run this hourly from a
# systemd timer or cron so a lost phone's key dies on its own — you don't
# have to notice or manually revoke.
#
# Usage:
#   bash auto-lock-server.sh                      # check + revoke if stale
#   MAX_IDLE_HOURS=6 bash auto-lock-server.sh     # stricter timeout
#   KILL_SESSIONS=false bash auto-lock-server.sh  # remove key, keep sessions
#
# Install: bash setup/install-auto-lock.sh  (systemd timer or cron)

set -euo pipefail

HEARTBEAT_FILE="${HEARTBEAT_FILE:-$HOME/.phone-heartbeat}"
AUTH_KEYS="$HOME/.ssh/authorized_keys"
MAX_IDLE_HOURS="${MAX_IDLE_HOURS:-24}"
PHONE_KEY_COMMENT="${PHONE_KEY_COMMENT:-termux-|iphone-|blink}"
KILL_SESSIONS="${KILL_SESSIONS:-true}"
LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mobile-terminal-ops"
LOG_FILE="$LOG_DIR/auto-lock.log"

mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

info() { echo -e "\033[0;36m[*]\033[0m $*"; }
warn() { echo -e "\033[0;33m[!]\033[0m $*"; }
err()  { echo -e "\033[0;31m[x]\033[0m $*"; }

if [ ! -f "$AUTH_KEYS" ]; then
    info "No authorized_keys file — nothing to do."
    exit 0
fi

# ── Is the heartbeat fresh? ───────────────────
if [ ! -f "$HEARTBEAT_FILE" ]; then
    warn "Heartbeat file missing ($HEARTBEAT_FILE). Treating as stale."
    HEARTBEAT_AGE_HOURS="missing"
    stale=true
else
    MAX_MINUTES=$((MAX_IDLE_HOURS * 60))
    if find "$HEARTBEAT_FILE" -mmin +"$MAX_MINUTES" | grep -q .; then
        HEARTBEAT_AGE_HOURS=$(find "$HEARTBEAT_FILE" -mmin +"$MAX_MINUTES" -printf '%T@\n' 2>/dev/null | awk -v now="$(date +%s)" '{printf "%.1f", (now-$1)/3600}')
        HEARTBEAT_AGE_HOURS="${HEARTBEAT_AGE_HOURS:-${MAX_IDLE_HOURS}+}"
        stale=true
    else
        stale=false
    fi
fi

if [ "$stale" = false ]; then
    info "Phone heartbeat is fresh (last heartbeat < ${MAX_IDLE_HOURS}h ago). No action."
    exit 0
fi

warn "Phone heartbeat is STALE (> ${MAX_IDLE_HOURS}h). Revoking phone key."

# ── Find and count matching phone keys ────────
MATCHING=$(grep -cE "ssh-ed25519 .* (${PHONE_KEY_COMMENT})" "$AUTH_KEYS" 2>/dev/null || echo 0)
if [ "$MATCHING" -eq 0 ]; then
    warn "No key matching PHONE_KEY_COMMENT='${PHONE_KEY_COMMENT}' found in $AUTH_KEYS."
    warn "Nothing revoked. Set PHONE_KEY_COMMENT to your phone key's comment"
    warn "(check: grep ssh-ed25519 $AUTH_KEYS)."
else
    # ── Revoke ────────────────────────────────
    cp "$AUTH_KEYS" "$AUTH_KEYS.bak.$(date +%Y%m%d-%H%M%S)"
    sed -i -E "/ssh-ed25519 .* (${PHONE_KEY_COMMENT})/d" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    ok_msg="Revoked $MATCHING phone key(s) from $AUTH_KEYS (stale ${HEARTBEAT_AGE_HOURS}h)."
    log "$ok_msg"
    echo -e "\033[0;32m[+]\033[0m $ok_msg"
fi

# ── Kill open SSH sessions (optional) ─────────
if [ "$KILL_SESSIONS" = "true" ]; then
    warn "Killing open SSH sessions (KILL_SESSIONS=true)..."
    # Only sessions arriving over the Tailscale net (100.64.0.0/10)
    for pid in $(pgrep -f 'sshd: .*@' 2>/dev/null || true); do
        if tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -qE '^SSH_CLIENT=100\.'; then
            kill "$pid" 2>/dev/null && log "Killed SSH session pid $pid (Tailscale client)"
        fi
    done
    ok_msg="Open Tailscale SSH sessions killed."
    log "$ok_msg"
    echo -e "\033[0;32m[+]\033[0m $ok_msg"
else
    info "KILL_SESSIONS=false — key revoked, existing sessions left alone."
fi

echo ""
warn "If this was a false alarm (phone was just off), re-add your key and reconnect:"
warn "  cat ~/.ssh/id_ed25519.pub   (on phone)"
warn "  echo '<pubkey>' >> ~/.ssh/authorized_keys   (on server)"