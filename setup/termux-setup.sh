#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1"; }

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║     Termux Mobile Terminal Setup          ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

info "Updating packages..."
pkg update -y && pkg upgrade -y

info "Installing essentials..."
pkg install -y \
    openssh \
    tmux \
    git \
    curl \
    wget \
    termux-api \
    ripgrep \
    fzf \
    man \
    which \
    python \
    nodejs \
    nmap

ok "Packages installed."

if [ ! -f ~/.ssh/id_ed25519 ]; then
    info "Generating ED25519 SSH key..."
    ssh-keygen -t ed25519 -C "termux-$(hostname)" -f ~/.ssh/id_ed25519 -N ""
    ok "SSH key generated: ~/.ssh/id_ed25519.pub"
else
    ok "SSH key already exists."
fi

info "Setting SSH config..."
cat > ~/.ssh/config << 'SSHCONF'
Host hunt
    HostName 100.68.188.37
    User kashoo
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
    ControlMaster auto
    ControlPath ~/.ssh/controlmasters/%r@%h:%p
    ControlPersist 10m

Host *.tailscale
    StrictHostKeyChecking accept-new
SSHCONF

mkdir -p ~/.ssh/controlmasters
chmod 700 ~/.ssh ~/.ssh/controlmasters
ok "SSH config written."

if ! grep -q 'export EDITOR' ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'BASHRC'

export EDITOR=nano
export TERM=xterm-256color

alias hunt='ssh hunt'
alias hunt-oc='ssh -t hunt "tmux new-session -A -s opencode \"cd ~/hunt && opencode\""'
alias oc='opencode'

tmux_smart_attach() {
    if tmux has-session -t hunt 2>/dev/null; then
        tmux attach-session -t hunt
    else
        tmux new-session -s hunt
    fi
}

hunt-re() {
    local retries=3
    while [ $retries -gt 0 ]; do
        ssh hunt "tmux new-session -A -s hunt" && return
        retries=$((retries - 1))
        [ $retries -gt 0 ] && warn "Connection dropped, retrying in 3s..." && sleep 3
    done
    err "Failed to reconnect after 3 attempts."
}
BASHRC
    ok "bashrc aliases added."
fi

ok "=== Termux setup complete! ==="
echo ""
info "Next steps:"
info "1. Add your public key to the server:"
info "   cat ~/.ssh/id_ed25519.pub"
info "   (copy this and run server-setup.sh on your server)"
info "2. Edit ~/.ssh/config and set your server's Tailscale IP"
info "3. Test: ssh hunt"
