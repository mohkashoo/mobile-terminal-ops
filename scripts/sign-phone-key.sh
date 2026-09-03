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

# Match the OLD raw key by its base64 blob, NOT the comment — the comment may
# differ when re-pasting, and a missed match leaves PERMANENT access behind.
KEY_BLOB=$(echo "$KEY" | awk '{print $2}')
if [ -z "$KEY_BLOB" ]; then
    err "Could not extract the key blob."
    rm -rf "$TMPDIR_SAFE"
    exit 1
fi

VALID_FROM="-1m"
VALID_TO="+${CERT_HOURS}h"
SERIAL="phone-$(date +%s)"
CERT_FILE="$TMPDIR_SAFE/phone-cert.pub"

info "Signing key → cert (principal=$PRINCIPAL, valid ${CERT_HOURS}h)..."
if [ "$DRY_RUN" = true ]; then
    warn "[DRY-RUN] Would run: ssh-keygen -s $CA_PRIV -I $SERIAL -n $PRINCIPAL -V ${VALID_FROM}:${VALID_TO} $TMPDIR_SAFE/phone.pub"
    echo ""
    info "(dry-run: no cert produced, nothing changed)"
    rm -rf "$TMPDIR_SAFE"
    exit 0
fi

SIGN_RC=0
# Redirect output so the tty stays clean (the CA passphrase prompt still reads
# from /dev/tty). Check the real exit status, not grep's.
ssh-keygen -s "$CA_PRIV" -I "$SERIAL" -n "$PRINCIPAL" -V "${VALID_FROM}:${VALID_TO}" "$TMPDIR_SAFE/phone.pub" >/dev/null 2>&1 || SIGN_RC=1
if [ "$SIGN_RC" -ne 0 ] || [ ! -f "$TMPDIR_SAFE/phone-cert.pub" ]; then
    err "Signing failed."
    rm -rf "$TMPDIR_SAFE"
    exit 1
fi

CERT=$(cat "$TMPDIR_SAFE/phone-cert.pub")
EXPIRES=$(ssh-keygen -L -f "$TMPDIR_SAFE/phone-cert.pub" 2>/dev/null | grep '^[[:space:]]*Valid' | sed 's/^[[:space:]]*//')

echo ""
ok "=== CERTIFICATE (valid ${CERT_HOURS}h, expires: ${EXPIRES:-check with ssh-keygen -L}) ==="
echo ""

# ── Install on the server: authorized_keys ────
AUTH_KEYS="$HOME/.ssh/authorized_keys"
touch "$AUTH_KEYS"; chmod 600 "$AUTH_KEYS"

# Order matters: append the CERT FIRST, then remove the old raw key. If the
# script is interrupted between the two, the phone still has a valid credential.
cp "$AUTH_KEYS" "$AUTH_KEYS.bak.$(date +%Y%m%d-%H%M%S)"
if grep -qF "$KEY_BLOB" "$AUTH_KEYS"; then
    echo "$CERT" >> "$AUTH_KEYS"
    # Remove only the RAW key line containing this blob (certs don't contain it).
    grep -vF "$KEY_BLOB" "$AUTH_KEYS" > "$AUTH_KEYS.tmp"
    mv "$AUTH_KEYS.tmp" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    ok "Old raw key replaced by the cert in $AUTH_KEYS."
else
    err "The pasted key's blob was NOT found in $AUTH_KEYS — adding cert anyway, but"
    err "the raw key is still active. Remove it manually:"
    err "  grep -vF '$KEY_BLOB' $AUTH_KEYS > \$AUTH_KEYS.tmp && mv \$AUTH_KEYS.tmp \$AUTH_KEYS"
    echo "$CERT" >> "$AUTH_KEYS"
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