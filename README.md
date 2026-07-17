<p align="center">
  <img src="https://github.com/mohkashoo/mobile-terminal-ops/raw/master/.github/social-preview.png" alt="Mobile Terminal Ops">
</p>

# Mobile Terminal Ops

**Turn your Android phone into a full remote pentest workstation — zero open ports, persistent tmux sessions, opencode integration, and one-tap reconnect.**

```
Phone (Termux) ──[Tailscale/WireGuard]──> Server (Ubuntu)
      │                                        │
      ├─ ssh key (ED25519)                     ├─ tmux + opencode
      ├─ clipboard sync (termux-clipboard)     ├─ persistent sessions
      └─ one-tap reconnect                     └─ bug hunting toolchain
```

---

## Why This Exists

Most bug hunters tether to a VPS or open port 22 on their home router. Both are attack surfaces. This setup uses **Tailscale** (WireGuard-based mesh VPN) so your server has **zero exposed ports** — it's invisible to Shodan, masscan, and your ISP. You connect from your phone over an encrypted overlay network.

Add **tmux persistence**, **opencode**, and **clipboard sync**, and you never lose context — disconnect mid-hunt, reconnect from the train, and pick up exactly where you left off.

---

## What You Get

| Feature | How |
|---|---|
| Zero open ports | Tailscale mesh VPN — no port forwarding |
| Key-only auth | ED25519 keys, passwords disabled |
| Persistent sessions | tmux resurrects your entire workspace |
| opencode ready | Pre-configured alias + session launcher |
| Clipboard sync | Copy from phone, paste on server (and vice versa) |
| One-tap connect | `ssh hunt` — that's it |
| Reconnect resilience | Auto-retry on network drop, same session |
| Bug hunting pipeline | Your tools (nuclei, ffuf, gf, etc.) ready on connect |

---

## Project Structure

```
mobile-terminal-ops/
├── README.md              # You are here
├── setup/
│   ├── termux-setup.sh    # Run this on your Android phone
│   └── server-setup.sh    # Run this on your Ubuntu server
├── scripts/
│   ├── connect.sh         # Quick-connect alias for Termux
│   ├── sync-clipboard.sh  # Bidirectional clipboard bridge
│   └── tmux-session.sh    # Persistent tmux workspace launcher
├── config/
│   ├── ssh-config         # ~/.ssh/config template
│   └── tailscale-hardening.md
└── .gitignore
```

---

## Quick Start

### 1. Tailscale (both devices)

```bash
# Server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Phone: install from Google Play, log into same account
```

Note the Tailscale IP of your server (`tailscale ip -4`).

### 2. Run the setup scripts

**On your phone (Termux):**
```bash
pkg install git -y
git clone https://github.com/kashoobest-droid/mobile-terminal-ops.git
cd mobile-terminal-ops
bash setup/termux-setup.sh
```

**On your server:**
```bash
cd mobile-terminal-ops
bash setup/server-setup.sh
```

The scripts handle: package installation, key generation, permission hardening, SSH config, and disabling password auth.

### 3. Connect

```bash
ssh hunt
```

That's it. First time you'll be prompted to confirm the host key.

---

## Usage Workflow

### Standard hunt session
```bash
ssh hunt                    # connect
tmux a -t hunt             # attach to persistent session
opencode                   # fire up opencode in the workspace
```

### Quick reconnect (after disconnect)
```bash
ssh hunt                   # automatically reattaches to tmux session
```

### Clipboard sync
```bash
# From phone to server:
termux-clipboard-get | ssh hunt "cat > ~/clipboard-in"

# From server to phone (pipe through ssh):
echo "target.com" | ssh hunt "cat"   # standard output back to phone
```

See `scripts/sync-clipboard.sh` for the automated version with `inotify` polling.

---

## Automation Scripts Detail

### `scripts/connect.sh`
One-liner ssh wrapper with:
- Auto-reconnect on network drop (up to 3 retries)
- Reattaches to `hunt` tmux session on connect
- Passes clipboard content from phone as stdin

### `scripts/sync-clipboard.sh`
Bidirectional clipboard sync daemon:
- Watches `~/.phone-clipboard` for changes
- Pushes/pulls via Termux:Clipboard API over SSH
- Useful for copying bug bounty target URLs between devices

### `scripts/tmux-session.sh`
Creates a tmux workspace with:
- **Pane 0:** opencode session in `~/hunt/` workspace
- **Pane 1:** Terminal for running tools (nuclei, ffuf, curl)
- **Pane 2:** HTOP / system monitor
- **Status bar** shows target IP, active tool, and connection status

---

## Security Hardening

| Setting | Why |
|---|---|
| `PasswordAuthentication no` | Key-only access, no brute force |
| `PermitRootLogin no` | Never log in as root |
| `~/.ssh/` permissions 700 | SSH refuses keys if group-writable |
| Tailscale ACLs | Restrict which devices can reach which ports |
| Fail2ban (optional) | Rate-limit auth failures on LAN |

See `config/tailscale-hardening.md` for advanced ACL rules.

---

## opencode Integration

The server setup script provisions a `~/.opencode.json` and adds a `hunt()` bash function that:

1. Checks Tailscale connectivity
2. Opens or reattaches tmux session
3. Launches opencode in your `~/hunt/` directory
4. Logs the session to `~/hunt/session.log`

Relevant alias added to `~/.bashrc`:
```bash
alias hunt-oc='ssh -t hunt "tmux new-session -A -s opencode \"cd ~/hunt && opencode\""'
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `ssh hunt` hangs | Check Tailscale is connected on both sides |
| `REMOTE HOST IDENTIFICATION CHANGED` | `ssh-keygen -R <TAILSCALE_IP>` |
| Permission denied (publickey) | `chmod 600 ~/.ssh/authorized_keys` on server |
| tmux session not found | Run `tmux new-session -s hunt` first time |
| Clipboard not syncing | Install `termux-clipboard-get/set` via `pkg install termux-api` |

---

## Why Tailscale vs. Alternatives

| Method | Open Ports | NAT Traversal | Speed | Complexity |
|---|---|---|---|---|
| **Tailscale** (this setup) | **0** | ✅ | ⚡ | Low |
| WireGuard directly | 1 (UDP) | ❌ requires public IP | ⚡ | Medium |
| ngrok / bore | 0 | ✅ | 🐢 | Low |
| Port forwarding | 1+ | ❌ | ⚡ | Low but risky |
| ZeroTier | 0 | ✅ | ⚡ | Medium |

---

## License

MIT — use it, fork it, improve it.
