#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1"; }

DRY_RUN=false
FORCE=false

usage() {
    echo "Usage: $0 [--dry-run] [--force]"
    echo "  --dry-run  Show what would change without applying anything"
    echo "  --force    Skip confirmation prompts"
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

run() {
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would run: $*"
    else
        "$@"
    fi
}

confirm() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    echo -en "${YELLOW}[?]${NC} $1 [y/N] "
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

detect_os() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        *)        echo "unknown" ;;
    esac
}

OS=$(detect_os)

if [ "$OS" = "unknown" ]; then
    err "Unsupported OS: $(uname -s)"
    err "This script supports Linux (Ubuntu/Debian) and macOS."
    exit 1
fi

info "Detected OS: $OS"

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║      Server Setup                         ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

if [ "$DRY_RUN" = true ]; then
    warn "Running in dry-run mode — no changes will be made."
    echo ""
fi

if [ "$(id -u)" -eq 0 ]; then
    err "Do not run as root. Run as your normal user."
    exit 1
fi

# ──────────────────────────────────────────────
# Package installation
# ──────────────────────────────────────────────
if [ "$OS" = "linux" ]; then
    info "Updating system..."
    run sudo apt update -y && run sudo apt upgrade -y

    info "Installing packages..."
    DEPS="tmux htop ripgrep fzf bat tree jq netcat-openbsd wireguard fail2ban ufw unzip build-essential"
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would install: $DEPS"
    else
        sudo apt install -y $DEPS
    fi
elif [ "$OS" = "macos" ]; then
    info "Checking Homebrew..."
    if ! command -v brew &>/dev/null; then
        err "Homebrew not found. Install it first:"
        err "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi

    info "Installing packages via Homebrew..."
    DEPS="tmux htop ripgrep fzf bat tree jq"
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would install: $DEPS"
    else
        brew install $DEPS 2>/dev/null || brew install $(echo $DEPS | sed 's/bat/bat-extras/')
    fi
fi
ok "Packages installed."

# ──────────────────────────────────────────────
# Tailscale
# ──────────────────────────────────────────────
info "Checking Tailscale..."
if ! command -v tailscale &>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would install and configure Tailscale"
    else
        if [ "$OS" = "linux" ]; then
            warn "Tailscale not found. Installing..."
            curl -fsSL https://tailscale.com/install.sh | sh
        elif [ "$OS" = "macos" ]; then
            warn "Tailscale not found. Install from: https://tailscale.com/download/mac"
            warn "Or via Homebrew: brew install --cask tailscale"
            warn "Then run: sudo tailscale up"
            warn "After that, re-run this script."
            confirm "Continue without Tailscale?" || exit 1
        fi
    fi
else
    ok "Tailscale is already installed."
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
    info "Tailscale IP: $TS_IP"
fi

# ──────────────────────────────────────────────
# Enable SSH server (macOS specific)
# ──────────────────────────────────────────────
if [ "$OS" = "macos" ]; then
    SSH_ENABLED=$(sudo systemsetup -getremotelogin 2>/dev/null || echo "Remote Login: Off")
    if echo "$SSH_ENABLED" | grep -q "Off"; then
        if confirm "Enable Remote Login (SSH server) on macOS?"; then
            if [ "$DRY_RUN" = true ]; then
                warn "[DRY-RUN] Would enable Remote Login via systemsetup"
            else
                run sudo systemsetup -setremotelogin on
                ok "Remote Login enabled."
            fi
        fi
    else
        ok "Remote Login already enabled."
    fi
fi

# ──────────────────────────────────────────────
# SSH key setup
# ──────────────────────────────────────────────
run mkdir -p ~/.ssh
run chmod 700 ~/.ssh

if [ ! -f ~/.ssh/authorized_keys ]; then
    run touch ~/.ssh/authorized_keys
fi

EXISTING_KEYS=$(grep -c 'ssh-ed25519\|ssh-rsa\|ecdsa\|ssh-ed448' ~/.ssh/authorized_keys 2>/dev/null || echo 0)
if [ "$EXISTING_KEYS" -gt 0 ]; then
    warn "You already have $EXISTING_KEYS key(s) in ~/.ssh/authorized_keys"
    confirm "Add another key (from your phone)?" || info "Skipping key addition."
else
    echo ""
    warn "=== PASTE YOUR PHONE'S PUBLIC KEY BELOW ==="
    warn "From your phone, run: cat ~/.ssh/id_ed25519.pub"
    warn "Then paste the output here and press Ctrl+D when done:"
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would read key from stdin and append to authorized_keys"
    else
        cat >> ~/.ssh/authorized_keys
        ok "Public key added."
    fi
fi

run chmod 600 ~/.ssh/authorized_keys
run chmod 700 ~/.ssh
run sudo chown -R "$USER:$USER" ~/.ssh

run mkdir -p ~/hunt ~/tools ~/wordlists

# ──────────────────────────────────────────────
# Shell config (bash on Linux, zsh on macOS)
# ──────────────────────────────────────────────
SHELL_CONFIG="$HOME/.bashrc"
[ "$OS" = "macos" ] && SHELL_CONFIG="$HOME/.zshrc"

if confirm "Add hunt aliases to $(basename "$SHELL_CONFIG")?"; then
    BACKUP="$SHELL_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would back up $SHELL_CONFIG to $BACKUP"
    else
        [ -f "$SHELL_CONFIG" ] && cp "$SHELL_CONFIG" "$BACKUP" && info "Backed up → $BACKUP"
        cat >> "$SHELL_CONFIG" << 'BASHRC'

export EDITOR=nano
export TERM=xterm-256color

alias oc='opencode'

hunt-session() {
    tmux new-session -A -s hunt
}
BASHRC
        ok "Aliases added to $(basename "$SHELL_CONFIG")."
    fi
fi

# ──────────────────────────────────────────────
# SSH hardening (Linux only — macOS manages its own)
# ──────────────────────────────────────────────
if [ "$OS" = "linux" ]; then
    echo ""
    info "SSH hardening preview:"
    info "  PasswordAuthentication → no"
    info "  PubkeyAuthentication → yes"
    info "  PermitRootLogin → no"
    info "  ClientAliveInterval → 30"
    info "  ClientAliveCountMax → 3"

    if confirm "Apply these SSH hardening settings?"; then
        if [ "$DRY_RUN" = true ]; then
            warn "[DRY-RUN] Would update /etc/ssh/sshd_config and restart sshd"
        else
            run sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
            run sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
            run sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
            run sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
            run sudo sed -i 's/^#\?UsePAM.*/UsePAM no/' /etc/ssh/sshd_config
            run sudo sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 30/' /etc/ssh/sshd_config
            run sudo sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config

            run sudo sshd -t && run sudo systemctl restart sshd
            ok "SSH hardened and restarted."
        fi
    fi
else
    info "Skipping SSH config hardening — macOS SSH is managed via System Settings."
    info "Just make sure 'Remote Login' is ON (it is if you enabled it above)."
fi

# ──────────────────────────────────────────────
# Firewall (UFW on Linux)
# ──────────────────────────────────────────────
if [ "$OS" = "linux" ] && command -v ufw &>/dev/null; then
    UFW_ACTIVE=$(sudo ufw status | head -1)
    if echo "$UFW_ACTIVE" | grep -q inactive || [ "$FORCE" = true ]; then
        if confirm "Enable UFW with Tailscale-only SSH access?"; then
            if [ "$DRY_RUN" = true ]; then
                warn "[DRY-RUN] Would configure UFW with Tailscale-only rules"
            else
                run sudo ufw --force reset
                run sudo ufw default deny incoming
                run sudo ufw default allow outgoing
                if command -v tailscale &>/dev/null; then
                    TAILSCALE_NET="100.64.0.0/10"
                    run sudo ufw allow from "$TAILSCALE_NET" to any port 22 proto tcp comment 'Tailscale SSH'
                    run sudo ufw allow from "$TAILSCALE_NET" to any port 8353 comment 'opencode port'
                fi
                run sudo ufw --force enable
                ok "UFW enabled — only Tailscale subnet can reach SSH."
            fi
        fi
    else
        ok "UFW already active."
    fi
elif [ "$OS" = "macos" ]; then
    info "Skipping firewall setup — macOS has its own firewall."
    info "Go to System Settings → Network → Firewall to configure if needed."
fi

# ──────────────────────────────────────────────
# Fail2ban
# ──────────────────────────────────────────────
if [ "$OS" = "linux" ] && [ -d /etc/fail2ban ]; then
    if confirm "Configure fail2ban for SSH?"; then
        if [ "$DRY_RUN" = true ]; then
            warn "[DRY-RUN] Would write /etc/fail2ban/jail.d/ssh-tailscale.conf"
        else
            run sudo tee /etc/fail2ban/jail.d/ssh-tailscale.conf > /dev/null << 'F2B'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
F2B
            run sudo systemctl restart fail2ban || run sudo fail2ban-client reload
            ok "fail2ban configured — 3 failed attempts = 24h ban."
        fi
    fi
elif [ "$OS" = "macos" ]; then
    if command -v fail2ban &>/dev/null || confirm "Install fail2ban via Homebrew?"; then
        if [ "$DRY_RUN" = true ]; then
            warn "[DRY-RUN] Would install fail2ban via brew and configure"
        else
            brew install fail2ban 2>/dev/null || true
            ok "fail2ban installed. Configure it manually:"
            info "  sudo cp /usr/local/etc/fail2ban/jail.conf /etc/fail2ban/jail.local"
            info "  sudo brew services start fail2ban"
        fi
    fi
fi

run mkdir -p ~/hunt
cat > ~/hunt/session.log 2>/dev/null << 'LOG'
# Hunt Session Log
# Started: $(date)
LOG

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Server setup complete!                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""
TS_IP=$(tailscale ip -4 2>/dev/null || echo "run 'tailscale ip -4' to find it")
info "Server Tailscale IP: $TS_IP"
info "Connect from phone:  ssh hunt"
info "Workspace:           ~/hunt/"
echo ""

if [ "$DRY_RUN" = true ]; then
    warn "This was a dry-run — no changes were made."
    warn "Run without --dry-run to apply."
fi
