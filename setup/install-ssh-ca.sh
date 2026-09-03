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
else
    info "Creating SSH CA keypair..."
    warn "Protect the CA private key with a passphrase — it can mint credentials"
    warn "into your server. A compromised CA = attacker-issued phone keys."
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would generate: ssh-keygen -t ed25519 -f $CA_PRIV"
    else
        ssh-keygen -t ed25519 -f "$CA_PRIV" -C "mobile-terminal-ops CA"
        chmod 600 "$CA_PRIV"; chmod 644 "$CA_PUB"
        ok "CA keypair created: $CA_PRIV (+ .pub)"
    fi
fi

# ── 2. Trust the CA in sshd ───────────────────
CA_LINE="TrustedUserCAKeys $CA_PUB"

if [ "$(uname -s)" = "Linux" ]; then
    if grep -q '^TrustedUserCAKeys' /etc/ssh/sshd_config 2>/dev/null; then
        warn "TrustedUserCAKeys already set in sshd_config — leaving as-is."
        info "Verify it points to $CA_PUB"
    else
        if [ "$DRY_RUN" = true ]; then
            warn "[DRY-RUN] Would append '$CA_LINE' to /etc/ssh/sshd_config and restart sshd"
        else
            echo "$CA_LINE" | sudo tee -a /etc/ssh/sshd_config > /dev/null
            sudo sshd -t && sudo systemctl restart sshd
            ok "sshd now trusts $CA_PUB."
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