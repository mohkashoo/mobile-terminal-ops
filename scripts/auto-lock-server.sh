#!/usr/bin/env bash
# Dead-man's switch for the "phone lost/stolen" risk.
#
# If the phone hasn't sent a heartbeat in MAX_IDLE_HOURS, this script:
#   1. Removes the phone's key from ~/.ssh/authorized_keys (no more logins)
#   2. Optionally kills open SSH sessions (KILL_SESSIONS=true, default false)
#
# Heartbeats are written automatically on every Tailscale SSH login via
# ~/.ssh/rc (see setup/install-auto-lock.sh). Run this hourly from a
# systemd timer or cron so a lost phone's key dies on its own — you don't
# have to notice or manually revoke.
#
# FAILURE DIRECTION: this script is designed to fail CLOSED. If the heartbeat
# is missing, stale, future-dated (clock skew), or unreadable, the key is
# treated as stale and revoked. The only way it stays permissive is if the
# scheduler itself never runs — verify with --check-health (see README).
#
# Usage:
#   bash auto-lock-server.sh                      # check + revoke if stale
#   MAX_IDLE_HOURS=6 bash auto-lock-server.sh     # stricter timeout
#   KILL_SESSIONS=true  bash auto-lock-server.sh  # also kill open sessions
#   bash auto-lock-server.sh --check-health       # is the watchdog itself alive?
#
# Install: bash setup/install-auto-lock.sh  (systemd timer or cron)

set -euo pipefail

HEARTBEAT_FILE="${HEARTBEAT_FILE:-$HOME/.phone-heartbeat}"
AUTH_KEYS="$HOME/.ssh/authorized_keys"
MAX_IDLE_HOURS="${MAX_IDLE_HOURS:-24}"
PHONE_KEY_COMMENT="${PHONE_KEY_COMMENT:-^(termux-|iphone-|blink)}"
KILL_SESSIONS="${KILL_SESSIONS:-false}"
LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mobile-terminal-ops"
LOG_FILE="$LOG_DIR/auto-lock.log"
STATE_FILE="$LOG_DIR/auto-lock-last-run"

mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

info() { echo -e "\033[0;36m[*]\033[0m $*"; }
ok()   { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[0;33m[!]\033[0m $*"; }
err()  { echo -e "\033[0;31m[x]\033[0m $*"; }

# ── --check-health: is the watchdog itself alive? ──
if [ "${1:-}" = "--check-health" ]; then
    echo "HEARTBEAT_FILE=$HEARTBEAT_FILE"
    echo "AUTH_KEYS=$AUTH_KEYS"
    echo "MAX_IDLE_HOURS=$MAX_IDLE_HOURS"
    echo "KILL_SESSIONS=$KILL_SESSIONS"
    echo ""
    if [ ! -f "$HEARTBEAT_FILE" ]; then
        warn "heartbeat: NEVER SET (no heartbeat file). Phone has not logged in since install."
    else
        echo "heartbeat file mtime: $(portable_mtime "$HEARTBEAT_FILE" 2>/dev/null || echo 'unreadable')"
    fi
    if [ -f "$STATE_FILE" ]; then
        echo "last watchdog run: $(cat "$STATE_FILE")"
        if find "$STATE_FILE" -mmin +"$((MAX_IDLE_HOURS * 60))" | grep -q .; then
            err "last run is older than MAX_IDLE_HOURS — the timer/cron is probably NOT firing!"
        else
            ok "last run is recent — scheduler looks healthy."
        fi
    else
        warn "no last-run marker yet — watchdog has never completed a run."
    fi
    echo ""
    echo "scheduler check:"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status mto-autolock.timer --no-pager 2>/dev/null | head -6 || true
        systemctl --user status mto-autolock.timer --no-pager 2>/dev/null | head -6 || true
    fi
    crontab -l 2>/dev/null | grep mto-auto-lock || echo "  (no cron entry)"
    exit 0
fi

# ── Portable mtime (Linux/BSD/busybox) ────────
portable_mtime() {
    case "$(uname -s)" in
        Linux) stat -c %Y "$1" 2>/dev/null ;;
        *)     stat -f %m "$1" 2>/dev/null ;;
    esac
}

if [ ! -f "$AUTH_KEYS" ]; then
    info "No authorized_keys file — nothing to do."
    date -u '+%Y-%m-%d %H:%M:%S UTC' > "$STATE_FILE"
    exit 0
fi

# ── Is the heartbeat fresh? (fail closed on any ambiguity) ──
if [ ! -f "$HEARTBEAT_FILE" ]; then
    warn "Heartbeat file missing ($HEARTBEAT_FILE). Treating as stale — revoking."
    stale=true
else
    MTIME=$(portable_mtime "$HEARTBEAT_FILE")
    if [ -z "$MTIME" ]; then
        warn "Heartbeat unreadable. Treating as stale — revoking."
        stale=true
    else
        NOW=$(date +%s)
        AGE_SEC=$(( NOW - MTIME ))
        if [ "$AGE_SEC" -lt 0 ]; then
            warn "Heartbeat mtime is in the FUTURE ($AGE_SEC s) — clock skew? Treating as stale."
            stale=true
        elif [ "$AGE_SEC" -gt $((MAX_IDLE_HOURS * 3600)) ]; then
            stale=true
        else
            stale=false
        fi
        HEARTBEAT_AGE_HOURS=$(awk -v s="$AGE_SEC" 'BEGIN { printf "%.1f", s/3600 }')
    fi
fi

if [ "$stale" = false ]; then
    info "Phone heartbeat is fresh (age ${HEARTBEAT_AGE_HOURS:-0}h < ${MAX_IDLE_HOURS}h). No action."
    date -u '+%Y-%m-%d %H:%M:%S UTC' > "$STATE_FILE"
    exit 0
fi

warn "Phone heartbeat is STALE (age ${HEARTBEAT_AGE_HOURS:-n/a}h > ${MAX_IDLE_HOURS}h). Revoking phone key."

# ── Find and count phone keys by COMMENT FIELD (raw keys + certs) ──
# Matches authorized_keys lines whose trailing comment field STARTS with the
# phone marker (e.g. "termux-phone"), not the admin's key. The comment field
# is anchored so "kashoo@termux-laptop" won't match a "termux-" admin key.
KEY_RE="^ssh-ed25519(-cert-v01@openssh\.com)? [^ ]+ ${PHONE_KEY_COMMENT#^}[^ ]*$"
MATCHING=$(grep -Ec "$KEY_RE" "$AUTH_KEYS" || true)

if [ "$MATCHING" -eq 0 ]; then
    warn "No key matching PHONE_KEY_COMMENT='${PHONE_KEY_COMMENT}' found in $AUTH_KEYS."
    warn "Nothing revoked. Check your phone key's comment:"
    warn "  grep ssh-ed25519 $AUTH_KEYS"
    warn "then set PHONE_KEY_COMMENT to match it (install-time env var)."
else
    cp "$AUTH_KEYS" "$AUTH_KEYS.bak.$(date +%Y%m%d-%H%M%S)"
    # Delete only lines whose comment field starts with the phone marker.
    # `|| true` is REQUIRED: grep exits 1 when no lines survive (all phone
    # keys revoked → empty file). Without it, set -e aborts before the mv
    # and the key stays active — fail-open on exactly the path that matters.
    grep -Ev "$KEY_RE" "$AUTH_KEYS" > "$AUTH_KEYS.tmp" || true
    mv "$AUTH_KEYS.tmp" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    ok_msg="Revoked $MATCHING phone key(s) from $AUTH_KEYS (stale ${HEARTBEAT_AGE_HOURS:-?}h)."
    log "$ok_msg"
    ok "$ok_msg"
fi

# ── Kill open Tailscale SSH sessions (optional, off by default) ──
if [ "$KILL_SESSIONS" = "true" ]; then
    warn "Killing open SSH sessions (KILL_SESSIONS=true)..."
    if [ -d /proc ]; then
        KILLED=0
        for pid in $(pgrep -f 'sshd: .*@' 2>/dev/null || true); do
            if tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -qE '^SSH_CLIENT=100\.'; then
                kill "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
            fi
        done
        log "Killed $KILLED Tailscale SSH session(s)."
        ok "Killed $KILLED Tailscale SSH session(s)."
    else
        warn "No /proc — cannot enumerate sessions on this OS. Key revoked; sessions left alone."
    fi
else
    info "KILL_SESSIONS=false (default) — key revoked, existing sessions left alone."
    info "Note: killing sessions also hits your own admin session over Tailscale; enable with"
    info "      KILL_SESSIONS=true if you want it."
fi

date -u '+%Y-%m-%d %H:%M:%S UTC' > "$STATE_FILE"

echo ""
warn "If this was a false alarm (phone was just off), re-add your key and reconnect:"
warn "  cat ~/.ssh/id_ed25519.pub   (on phone)"
warn "  echo '<pubkey>' >> ~/.ssh/authorized_keys   (on server)"