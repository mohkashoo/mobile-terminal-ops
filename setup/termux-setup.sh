#!/data/data/com.termux/files/usr/bin/bash
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
    echo "  --force    Skip confirmation prompts and overwrite existing config"
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

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║     Termux Mobile Terminal Setup          ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

if [ "$DRY_RUN" = true ]; then
    warn "Running in dry-run mode — no changes will be made."
    echo ""
fi

info "Updating packages..."
run pkg update -y && run pkg upgrade -y

info "Installing essentials..."
PKGS="openssh tmux git curl wget termux-api ripgrep fzf man which python nodejs nmap"
if [ "$DRY_RUN" = true ]; then
    warn "[DRY-RUN] Would install: $PKGS"
else
    pkg install -y $PKGS
fi
ok "Packages installed."

if [ ! -f ~/.ssh/id_ed25519 ]; then
    info "Generating ED25519 SSH key..."
    if [ "$DRY_RUN" = true ]; then
        warn "[DRY-RUN] Would generate: ssh-keygen -t ed25519"
    else
        ssh-keygen -t ed25519 -C "termux-$(hostname)" -f ~/.ssh/id_ed25519 -N ""
        ok "SSH key generated: ~/.ssh/id_ed25519.pub"
    fi
else
    ok "SSH key already exists at ~/.ssh/id_ed25519"
fi

if grep -q "Host hunt" ~/.ssh/config 2>/dev/null; then
    warn "SSH config already has a 'Host hunt' entry — skipping."
    warn "Edit ~/.ssh/config manually if you need to update the IP."
else
    if confirm "Write SSH config for 'hunt' host?"; then
        info "You'll need to edit the HostName (Tailscale IP) after setup."
        if [ "$DRY_RUN" = true ]; then
            warn "[DRY-RUN] Would write SSH config to ~/.ssh/config"
        else
            BACKUP="$HOME/.ssh/config.backup.$(date +%Y%m%d_%H%M%S)"
            [ -f ~/.ssh/config ] && cp ~/.ssh/config "$BACKUP" && info "Backed up ~/.ssh/config → $BACKUP"
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
            run mkdir -p ~/.ssh/controlmasters
            run chmod 700 ~/.ssh ~/.ssh/controlmasters
            ok "SSH config written. Edit ~/.ssh/config to set your server IP."
        fi
    fi
fi

if grep -q "alias hunt=" ~/.bashrc 2>/dev/null; then
    ok "bashrc aliases already present — skipping."
else
    if confirm "Add ssh aliases to ~/.bashrc?"; then
        if [ "$DRY_RUN" = true ]; then
            warn "[DRY-RUN] Would append aliases to ~/.bashrc"
        else
            BACKUP="$HOME/.bashrc.backup.$(date +%Y%m%d_%H%M%S)"
            [ -f ~/.bashrc ] && cp ~/.bashrc "$BACKUP" && info "Backed up ~/.bashrc → $BACKUP"
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
    fi
fi

echo ""
ok "=== Termux setup complete! ==="
echo ""
info "Next steps:"
info "1. Show your public key: cat ~/.ssh/id_ed25519.pub"
info "2. Copy that key, then run server-setup.sh on your Ubuntu server"
info "3. Edit ~/.ssh/config and update the HostName to your server's Tailscale IP"
info "4. Test the connection: ssh hunt"
echo ""

if [ "$DRY_RUN" = true ]; then
    warn "This was a dry-run — no changes were made."
    warn "Run without --dry-run to apply."
fi
