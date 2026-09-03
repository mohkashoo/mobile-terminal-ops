#!/usr/bin/env bash
# Install a local SSH CA for short-lived phone credentials.
#
# One ED25519 key in authorized_keys = permanent access until YOU revoke it.
# With an SSH CA, the phone's key is signed into a CERTIFICATE that expires
# (default 48h). A lost phone's credential dies on its own — no manual revoke.
#
# This script (run on the SERVER):
#   1. Creates a local CA keypair  ~/.ssh/mto-ca(.pub)  (passphrase-protected)
#   2. Tells sshd to trust it as a CA (TrustedUserCAKeys)
#   3. Restarts sshd
#
# Then sign the phone's key with scripts/sign-phone-key.sh.
#
# Usage:
#   bash setup/install-ssh-ca.sh
#   --dry-run  preview only

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; }

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

run() {
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would run: $*"
    else
        "$@"
    fi
}

if [ "$(id -u)" -eq 0 ]; then
    err "Do not run as root."
    exit 1
fi

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║     SSH CA Setup (short-lived certs)       ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

CA_PRIV="$HOME/.ssh/mto-ca"
CA_PUB="$HOME/.ssh/mto-ca.pub"

# ── 1. Create the CA keypair ──────────────────
if [ -f "$CA_PRIV" ]; then
    ok "CA key already exists: $CA_PRIV"
    # Verify the EXISTING key is not empty-passphrase (a leaked unencrypted CA
    # can mint unlimited certs into the server).
    if ssh-keygen -y -P '' -f "$CA_PRIV" >/dev/null 2>&1; then
        err "CA private key has an EMPTY passphrase — anyone with this file can mint"
        err "certificates into your server. Protect it:"
        err "  ssh-keygen -p -f $CA_PRIV"
        exit 1
    fi
else
    info "Creating SSH CA keypair..."
    warn "Protect the CA private key with a passphrase — it can mint credentials"
    warn "into your server. A compromised CA = attacker-issued phone keys."
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would generate: ssh-keygen -t ed25519 -f $CA_PRIV"
    else
        ssh-keygen -t ed25519 -f "$CA_PRIV" -C "mobile-terminal-ops CA"
        chmod 600 "$CA_PRIV"; chmod 644 "$CA_PUB"
        # Fail hard if the key ended up unencrypted (e.g. Enter pressed twice).
        if ssh-keygen -y -P '' -f "$CA_PRIV" >/dev/null 2>&1; then
            err "CA key was created with an EMPTY passphrase. Refusing to proceed."
            err "Delete $CA_PRIV and re-run, entering a real passphrase."
            exit 1
        fi
        ok "CA keypair created: $CA_PRIV (+ .pub)"
    fi
fi

# ── 2. Trust the CA in sshd ───────────────────
CA_LINE="TrustedUserCAKeys $CA_PUB"

check_ca_active() {
    # Confirm sshd is actually honoring our CA, not a drop-in or old value.
    if sudo sshd -T 2>/dev/null | grep -qi "trustedusercakeys.*${CA_PUB}"; then
        return 0
    fi
    return 1
}

if [ "$(uname -s)" = "Linux" ]; then
    if grep -qE '^[[:space:]]*TrustedUserCAKeys' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
        warn "TrustedUserCAKeys already set somewhere in sshd config."
        if [ "$DRY_RUN" = true ]; then
            warn "[DRY-RUN] Would verify it resolves to $CA_PUB"
        elif check_ca_active; then
            ok "Confirmed: sshd currently trusts $CA_PUB."
        else
            err "sshd has a TrustedUserCAKeys directive but it is NOT resolving to $CA_PUB."
            err "Check /etc/ssh/sshd_config and /etc/ssh/sshd_config.d/*.conf and fix"
            err "the conflict before relying on certs."
            exit 1
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            warn "[DRY-RUN] Would append '$CA_LINE' to /etc/ssh/sshd_config and restart sshd"
        else
            echo "$CA_LINE" | sudo tee -a /etc/ssh/sshd_config > /dev/null
            if sudo sshd -t && sudo systemctl restart sshd && check_ca_active; then
                ok "sshd now trusts $CA_PUB (verified with sshd -T)."
            else
                err "sshd did not come up with the CA trust. Check 'sudo sshd -t'."
                exit 1
            fi
        fi
    fi
elif [ "$(uname -s)" = "Darwin" ]; then
    warn "macOS: add '$CA_LINE' to /etc/ssh/sshd_config manually, then:"
    warn "  sudo launchctl kickstart -k system/com.openssh.sshd"
else
    err "Unsupported OS."
    exit 1
fi

echo ""
ok "=== SSH CA ready ==="
echo ""
info "Next: sign your phone's key (paste its ~/.ssh/id_ed25519.pub):"
info "  bash scripts/sign-phone-key.sh"
info ""
info "Certs default to 48h validity. A lost phone's key then dies on its own."

if [ "$DRY_RUN" = true ]; then
    warn "This was a dry-run — nothing was applied."
fi