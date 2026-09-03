#!/usr/bin/env bash
# Tailscale account + tailnet hardening for mobile-terminal-ops.
#
# This is the FIRST-CLASS hardening step for the "Tailscale compromised" and
# "phone lost/stolen" threat-model rows. It walks you through:
#   1. 2FA on the Tailscale account            (manual — admin console)
#   2. Tailnet Lock (node-signing)             (CLI + manual confirm)
#   3. SSH-only ACL phone -> server            (policy JSON — admin console)
#
# Run this AFTER server-setup.sh, on the server:
#   bash setup/tailscale-hardening.sh
#
# Flags: --dry-run (preview only), --force (skip confirmations)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; }

DRY_RUN=false
FORCE=false

usage() {
    echo "Usage: $0 [--dry-run] [--force]"
    echo "  --dry-run  Show what would change without applying anything"
    echo "  --force    Skip confirmation prompts (CLI steps still run)"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --help|-h) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
done

confirm() {
    [ "$FORCE" = true ] && return 0
    echo -en "${YELLOW}[?]${NC} $1 [y/N] "
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

run() {
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would run: $*"
    else
        "$@"
    fi
}

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║     Tailscale Hardening                    ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

if [ "$(id -u)" -eq 0 ]; then
    err "Do not run as root. Run as your normal user (sudo is used where needed)."
    exit 1
fi

if ! command -v tailscale &>/dev/null; then
    err "tailscale CLI not found. Install it first (see README Quick Start)."
    exit 1
fi

TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
info "Detected tailscale on: $TS_IP"
echo ""

# ──────────────────────────────────────────────
# 1. Two-factor authentication on the account
# ──────────────────────────────────────────────
echo ""
info "STEP 1/3 — Enable 2FA on your Tailscale account"
echo ""
warn "This cannot be automated from the CLI. Do it once:"
warn "  1. Log in at https://login.tailscale.com/admin/settings"
warn "  2. Enable 2FA (TOTP app). The admin console will require it going forward."
echo ""
if confirm "Have you enabled (or do you already have) 2FA on the Tailscale account?"; then
    ok "2FA acknowledged."
else
    warn "2FA not confirmed. Aborting — this step is mandatory for the threat model."
    exit 1
fi

# ──────────────────────────────────────────────
# 2. Tailnet Lock (node-signing)
# ──────────────────────────────────────────────
echo ""
info "STEP 2/3 — Tailnet Lock (nodes must be signed to join the tailnet)"
echo ""
warn "Tailnet Lock means a compromised control server or a rogue device CANNOT"
warn "join or be added to your tailnet without a trusted node's signature key."
echo ""

LOCK_STATUS=$(tailscale lock status 2>/dev/null || echo "not-enabled")
if echo "$LOCK_STATUS" | grep -qi "no node keys\|not enabled\|error"; then
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would enable Tailnet Lock via: sudo tailscale lock init"
        warn "[DRY-RUN] Would print the key to sign each other device."
    else
        if confirm "Enable Tailnet Lock on this node now? (recommended)"; then
            sudo tailscale lock init
            echo ""
            warn "The command above printed a node key. SIGN YOUR PHONE NODE with it:"
            warn "  On the phone:  tailscale lock status      # copy its node key"
            warn "  On this host:  sudo tailscale lock add-key <phone-node-key>"
            warn "Keep the lock key safe — it's the tailnet's trust anchor."
            echo ""
            if confirm "Done — phone node signed and lock enabled?"; then
                ok "Tailnet Lock acknowledged."
            else
                warn "Tailnet Lock init was run; sign the phone key before you rely on it."
            fi
        else
            warn "Skipping Tailnet Lock. Revisit this — it is the real answer to"
            warn "'what if Tailscale itself is compromised'."
        fi
    fi
else
    ok "Tailnet Lock is already enabled."
    tailscale lock status 2>/dev/null | head -20
fi

# ──────────────────────────────────────────────
# 3. SSH-only ACL (phone → server :22)
# ──────────────────────────────────────────────
echo ""
info "STEP 3/3 — ACL: phone → server, SSH ONLY"
echo ""
warn "Default tailnet ACLs let every node talk to every other node on all ports."
warn "For this setup the phone should ONLY be able to reach the server on port 22"
warn "(and the server reaches the tailnet as it needs)."
echo ""

if [ "$DRY_RUN" = true ]; then
    warn "[DRY-RUN] Would write ACL policy template to config/tailscale-acl.json"
else
    mkdir -p "$(cd "$(dirname "$0")/.." && pwd)/config"
    ACL_FILE="$(cd "$(dirname "$0")/.." && pwd)/config/tailscale-acl.json"
    cat > "$ACL_FILE" << 'ACL'
{
  "acls": [
    {
      "action": "accept",
      "src":    ["tag:phone"],
      "dst":    ["tag:server:22"]
    },
    {
      "action": "accept",
      "src":    ["tag:server"],
      "dst":    ["*:*"]
    }
  ],
  "tagOwners": {
    "tag:phone":  ["you@github"],
    "tag:server": ["you@github"]
  },
  "ssh": []
}
ACL
    ok "Wrote ACL template → $ACL_FILE"
    echo ""
    info "Apply it (manual — admin console):"
    info "  1. https://login.tailscale.com/admin/acls"
    info "  2. Replace the policy with the contents of config/tailscale-acl.json"
    info "  3. Change 'you@github' in tagOwners to YOUR tailnet identity"
    info "  4. Tag your devices so the ACL applies:"
    info "       server: sudo tailscale set --advertise-tags=tag:server"
    info "       phone:  tailscale set --advertise-tags=tag:phone"
    echo ""
    if confirm "Have you applied the ACL and tagged both devices?"; then
        ok "ACL acknowledged."
    else
        warn "ACL not confirmed. Revisit before exposing the server to the tailnet."
    fi
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Tailscale hardening complete          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""
info "Verify:  tailscale status"
info "Verify:  tailscale lock status"
info "Verify:  tailscale ping <server-ip>"

if [ "$DRY_RUN" = true ]; then
    warn "This was a dry-run — nothing was applied."
fi