#!/bin/sh
# iSH (Alpine Linux) setup for iPhone
# Run this inside iSH on your iPhone
#
# iSH is a free Alpine Linux environment for iOS.
# It's not as full-featured as Termux, but it works for SSH.
#
# Usage:
#   apk add git
#   git clone https://github.com/mohkashoo/mobile-terminal-ops.git
#   cd mobile-terminal-ops
#   bash setup/iphone-ish.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1"; }

NO_PASSPHRASE=false
I_UNDERSTAND_RISK=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-passphrase) NO_PASSPHRASE=true; shift ;;
        --i-understand-the-risk) I_UNDERSTAND_RISK=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--no-passphrase --i-understand-the-risk]"
            echo "  A passphrase on your SSH key is REQUIRED. Generating an unencrypted key"
            echo "  requires both --no-passphrase AND --i-understand-the-risk."
            exit 0 ;;
        *) err "Unknown option: $1"; exit 1 ;;
    esac
done

if [ "$NO_PASSPHRASE" = true ] && [ "$I_UNDERSTAND_RISK" != true ]; then
    err "--no-passphrase requires --i-understand-the-risk. Refusing to generate an unencrypted key."
    exit 1
fi

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║     iPhone (iSH) Setup                    ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

info "Updating packages..."
apk update && apk upgrade

info "Installing essentials..."
apk add openssh tmux git curl wget ripgrep fzf ncurses man-db python3 nmap openssh-keygen

ok "Packages installed."

if [ ! -f ~/.ssh/id_ed25519 ]; then
    info "Generating ED25519 SSH key..."
    if [ "$NO_PASSPHRASE" = true ]; then
        warn "Generating UNENCRYPTED key because you passed --no-passphrase --i-understand-the-risk."
        ssh-keygen -t ed25519 -C "iphone-ish-$(hostname)" -f ~/.ssh/id_ed25519 -N ""
    else
        warn "A passphrase is REQUIRED. If your phone is lost or stolen, an unencrypted key"
        warn "hands the attacker your server. Enter a strong passphrase when prompted."
        ssh-keygen -t ed25519 -C "iphone-ish-$(hostname)" -f ~/.ssh/id_ed25519
    fi
    ok "SSH key generated: ~/.ssh/id_ed25519.pub"
else
    ok "SSH key already exists."
    if [ -n "$(ssh-keygen -y -P '' -f ~/.ssh/id_ed25519 2>/dev/null)" ]; then
        warn "Existing key has NO passphrase. Protect it: ssh-keygen -p -f ~/.ssh/id_ed25519"
    fi
fi

info "Setting up SSH config..."
cat > ~/.ssh/config << 'SSHCONF'
Host hunt
    HostName 100.68.188.37
    User kashoo
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
    StrictHostKeyChecking accept-new
SSHCONF

chmod 600 ~/.ssh/config
chmod 700 ~/.ssh
ok "SSH config written."

cat >> ~/.bashrc << 'BASHRC'

alias hunt='ssh hunt'
alias oc-session='ssh -t hunt "tmux new-session -A -s hunt"'
BASHRC
ok "Aliases added to ~/.bashrc"

echo ""
ok "=== iSH setup complete! ==="
echo ""
info "Next steps:"
info "1. Show your public key:"
info "   cat ~/.ssh/id_ed25519.pub"
info "2. Copy the key and run server-setup.sh on your server"
info "3. Edit ~/.ssh/config and change HostName to your server's Tailscale IP"
info ""
warn "NOTE: iSH can't run in the background on iOS."
warn "The SSH session will stay active as long as iSH is open."
warn "For background SSH, consider Blink Shell instead."
