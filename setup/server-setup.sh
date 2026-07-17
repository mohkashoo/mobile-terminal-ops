#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1"; }

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║      Server Hardening & Setup             ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

if [ "$(id -u)" -eq 0 ]; then
    err "Do not run as root. Run as your normal user."
    exit 1
fi

info "Updating system..."
sudo apt update -y && sudo apt upgrade -y

info "Installing packages..."
sudo apt install -y \
    tmux \
    htop \
    ripgrep \
    fzf \
    bat \
    tree \
    jq \
    netcat-openbsd \
    wireguard \
    fail2ban \
    ufw \
    unzip \
    build-essential

ok "Packages installed."

info "Checking Tailscale..."
if ! command -v tailscale &>/dev/null; then
    warn "Tailscale not found. Installing..."
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale up
    ok "Tailscale installed and authenticated."
else
    ok "Tailscale is already installed."
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
    info "Tailscale IP: $TS_IP"
fi

mkdir -p ~/.ssh
chmod 700 ~/.ssh

if [ ! -f ~/.ssh/authorized_keys ]; then
    touch ~/.ssh/authorized_keys
fi

echo ""
warn "=== PASTE YOUR PHONE'S PUBLIC KEY BELOW ==="
warn "(from: cat ~/.ssh/id_ed25519.pub on your phone)"
warn "Press Ctrl+D when done:"
cat >> ~/.ssh/authorized_keys

chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
sudo chown -R "$USER:$USER" ~/.ssh

ok "Public key added."

mkdir -p ~/hunt ~/tools ~/wordlists

cat >> ~/.bashrc << 'BASHRC'

export EDITOR=nano
export TERM=xterm-256color

alias oc='opencode'

hunt-session() {
    tmux new-session -A -s hunt
}

alias oc-session='ssh -t localhost "tmux new-session -A -s opencode \"cd ~/hunt && opencode\""'
BASHRC

if ! grep -q 'HISTFILE' ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'HISTORY'
export HISTFILESIZE=10000000
export HISTSIZE=1000000
export HISTTIMEFORMAT="%F %T "
export HISTCONTROL=ignoredups
HISTORY
fi

ok "bashrc configured."

info "Hardening SSH..."
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?UsePAM.*/UsePAM no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 30/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config

sudo sshd -t && sudo systemctl restart sshd
ok "SSH hardened and restarted."

if sudo ufw status | grep -q inactive; then
    info "Enabling UFW..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    if command -v tailscale &>/dev/null; then
        TAILSCALE_NET="100.64.0.0/10"
        sudo ufw allow from "$TAILSCALE_NET" to any port 22 proto tcp comment 'Tailscale SSH'
        sudo ufw allow from "$TAILSCALE_NET" to any port 8353 comment 'opencode port'
    fi
    sudo ufw --force enable
    ok "UFW enabled — only Tailscale subnet can reach SSH."
else
    ok "UFW already active."
fi

info "Setting up fail2ban for SSH..."
if [ -d /etc/fail2ban ]; then
    sudo tee /etc/fail2ban/jail.d/ssh-tailscale.conf > /dev/null << 'F2B'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
F2B
    sudo systemctl restart fail2ban || sudo fail2ban-client reload
    ok "fail2ban configured."
fi

cat > ~/hunt/session.log 2>/dev/null << 'LOG'
# Hunt Session Log
# Started: $(date)
LOG

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Server setup complete!                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""
info "Server Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'check manually')"
info "Connect from phone:  ssh hunt"
info "Workspace:           ~/hunt/"
info ""
info "Next: logout, then from Termux run: ssh hunt"
