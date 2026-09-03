#!/usr/bin/env bash
# Sign a phone's public key into a SHORT-LIVED SSH certificate.
#
# Run on the SERVER (after setup/install-ssh-ca.sh). Paste the phone's
# ~/.ssh/id_ed25519.pub. You get a cert valid for CERT_HOURS (default 48),
# after which the phone's access expires on its own — nothing to remember.
#
# Usage:
#   bash scripts/sign-phone-key.sh [--hours 48] [--principal USER]
#       --hours       cert lifetime in hours (default 48)
#       --principal   SSH username the cert grants (default: current user)
#       --dry-run     show commands without signing

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; }

CA_PRIV="$HOME/.ssh/mto-ca"
CERT_HOURS=48
PRINCIPAL="$USER"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hours) CERT_HOURS="$2"; shift 2 ;;
        --principal) PRINCIPAL="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--hours 48] [--principal USER]"
            exit 0 ;;
        *) err "Unknown option: $1"; exit 1 ;;
    esac
done

if [ ! -f "$CA_PRIV" ]; then
    err "No CA found at $CA_PRIV. Run setup/install-ssh-ca.sh first."
    exit 1
fi

echo ""
warn "=== PASTE THE PHONE'S PUBLIC KEY BELOW ==="
warn "From the phone: cat ~/.ssh/id_ed25519.pub"
warn "Then press Ctrl+D when done."
KEY=$(cat)
if [ -z "$KEY" ] || ! echo "$KEY" | grep -q '^ssh-ed25519 '; then
    err "No valid ssh-ed25519 public key read."
    exit 1
fi

TMPDIR_SAFE=$(mktemp -d)
echo "$KEY" > "$TMPDIR_SAFE/phone.pub"

VALID_FROM="-1m"
VALID_TO="+${CERT_HOURS}h"
SERIAL="phone-$(date +%s)"
CERT_FILE="$TMPDIR_SAFE/phone-cert.pub"

info "Signing key → cert (principal=$PRINCIPAL, valid ${CERT_HOURS}h)..."
if [ "$DRY_RUN" = true ]; then
    warn "[DRY-RUN] Would run: ssh-keygen -s $CA_PRIV -I $SERIAL -n $PRINCIPAL -V ${VALID_FROM}:${VALID_TO} $TMPDIR_SAFE/phone.pub"
else
    ssh-keygen -s "$CA_PRIV" -I "$SERIAL" -n "$PRINCIPAL" -V "${VALID_FROM}:${VALID_TO}" "$TMPDIR_SAFE/phone.pub" 2>&1 | grep -v '^Signed user key' || true
    [ -f "$TMPDIR_SAFE/phone-cert.pub" ] || { err "Signing failed."; exit 1; }
fi

CERT=$(cat "$CERT_FILE")
EXPIRES=$(ssh-keygen -L -f "$CERT_FILE" 2>/dev/null | grep '^[[:space:]]*Valid' | sed 's/^[[:space:]]*//')

echo ""
ok "=== CERTIFICATE (valid ${CERT_HOURS}h, expires: ${EXPIRES:-check with ssh-keygen -L}) ==="
echo ""

# ── Install on the server: authorized_keys ────
AUTH_KEYS="$HOME/.ssh/authorized_keys"
if [ "$DRY_RUN" = true ]; then
    warn "[DRY-RUN] Would install the cert into $AUTH_KEYS"
else
    touch "$AUTH_KEYS"; chmod 600 "$AUTH_KEYS"
    # Remove the phone's old raw key, then add the cert line
    PHONE_COMMENT=$(echo "$KEY" | awk '{print $NF}')
    [ -n "$PHONE_COMMENT" ] && sed -i "/ssh-ed25519 .* ${PHONE_COMMENT}/d" "$AUTH_KEYS"
    echo "$CERT" >> "$AUTH_KEYS"
    ok "Cert installed into $AUTH_KEYS (old raw key removed)."
fi

echo ""
info "1. ON THE PHONE — save the cert next to your key (exact):"
info "   pico ~/.ssh/id_ed25519-cert.pub"
info "   paste the certificate text below, save, then: chmod 600 ~/.ssh/id_ed25519-cert.pub"
echo ""
info "2. Connect as usual:"
info "   ssh hunt"
info "   OpenSSH auto-presents id_ed25519-cert.pub with your key."
echo ""
info "3. When this cert expires, run this script again to re-sign."
info "   A lost phone is now time-limited, not permanently trusted."
echo ""
info "Certificate:"
echo "$CERT"

rm -rf "$TMPDIR_SAFE"