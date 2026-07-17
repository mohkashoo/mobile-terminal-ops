<p align="center">
  <img src="https://github.com/mohkashoo/mobile-terminal-ops/raw/master/.github/social-preview.png" alt="Mobile Terminal Ops">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/tested-Ubuntu%2024.04%20%7C%20Termux%20v0.118-blue" alt="Tested On">
  <img src="https://img.shields.io/badge/shell-bash-lightgrey" alt="Shell">
</p>

# Mobile Terminal Ops

**Your Android phone becomes a full remote hacking workstation. Zero open ports. Persistent tmux. opencode ready. One-tap reconnect.**

<p align="center">
  <img src="https://github.com/mohkashoo/mobile-terminal-ops/raw/master/assets/demo.gif" alt="Demo — Termux SSH into server, launching opencode + naabu port scan">
  <br>
  <em>Termux → SSH → server → opencode running naabu on google.com</em>
</p>

```
Phone (Termux) ──[Tailscale/WireGuard]──> Server (Ubuntu)
      │                                        │
      ├─ ssh key (ED25519)                     ├─ tmux + opencode
      ├─ clipboard sync (termux-clipboard)     ├─ persistent sessions
      └─ one-tap reconnect                     └─ bug hunting toolchain
```

---

## Security Model & Known Risks

This setup is secure **as long as your phone is secure**. Here's the honest threat model:

| Scenario | Risk | How I Handle It |
|---|---|---|
| **Phone is lost/stolen** | Someone has your SSH key and can reach your server via Tailscale | Revoke the key immediately from the server (`ssh-keygen -R <IP>` then remove from `authorized_keys`). Also de-authorize the device in Tailscale admin console. |
| **Phone is compromised (malware)** | Attacker can SSH into your server with your key | Use a strong screen lock. Don't root your phone. Consider adding a passphrase to your SSH key (`ssh-keygen -p -f ~/.ssh/id_ed25519`). |
| **Tailscale compromise** | Someone controls the coordination server | Tailscale is open-source and end-to-end encrypted. Your traffic is encrypted with WireGuard keys that never leave your devices. Still — don't put all your trust in one layer. |
| **Server compromise** | Someone breaks into your server through another service | UFW limits access to the Tailscale subnet only. fail2ban rate-limits auth attempts. No other services are exposed. |
| **Key rotation** | You want to replace an old key | Add the new key to `~/.ssh/authorized_keys`, remove the old one. No need to re-run the full setup. |

**Bottom line:** If your phone is lost, act fast — remove the key from `authorized_keys` and de-auth from Tailscale. If you're paranoid, add a passphrase to your SSH key.

---

## Why?

Every bug hunter I know either rents a VPS or opens port 22 on their home router. Both suck.

- VPS costs money and your tools aren't there
- Opening port 22 means Shodan, masscan, and every bot in the world knows your IP

This setup uses **Tailscale** — a WireGuard-based mesh VPN. Your server has **zero exposed ports**. It doesn't exist on the public internet. You connect from your phone over an encrypted tunnel that only your devices can use.

And with **tmux persistence** + **opencode** + **clipboard sync**, you can disconnect mid-hunt, go outside, come back, reconnect from your phone, and pick up **exactly** where you left off. No context loss.

---

## What You're Getting

| Feature | How It Works |
|---|---|
| Zero open ports | Tailscale mesh VPN — no port forwarding needed |
| Key-only auth | ED25519 keys, passwords disabled completely |
| Persistent sessions | tmux saves your workspace across disconnects |
| opencode integration | One alias launches opencode in your hunt directory |
| Clipboard sync | Copy on phone → paste on server. Or the other way |
| One-tap connect | Just type `ssh hunt` and you're in |
| Auto-reconnect | Drops your connection? Retries 3 times automatically |
| Tools ready | nuclei, ffuf, gf, naabu — whatever you use, it's there |

---

## Project Layout

```
mobile-terminal-ops/
├── README.md
├── setup/
│   ├── termux-setup.sh    # Run this on your phone (Termux)
│   └── server-setup.sh    # Run this on your Ubuntu laptop/server
├── scripts/
│   ├── connect.sh         # Smart reconnect wrapper
│   ├── sync-clipboard.sh  # Copy stuff between phone and server
│   └── tmux-session.sh    # Launches a 3-pane tmux layout
├── config/
│   ├── ssh-config         # SSH config template for Termux
│   └── tailscale-hardening.md
└── .gitignore
```

---

## Quick Start (5 Minutes)

### 1. Install Tailscale on both devices

```bash
# On your Ubuntu server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# On your Android phone — grab it from Google Play, log into the same account
```

After that, run `tailscale ip -4` on your server and write down the IP (looks like `100.x.x.x`).

### 2. Run the setup scripts

**On your phone (open Termux):**
```bash
pkg install git -y
git clone https://github.com/mohkashoo/mobile-terminal-ops.git
cd mobile-terminal-ops
bash setup/termux-setup.sh
```

**On your server:**
```bash
cd mobile-terminal-ops
bash setup/server-setup.sh
```

Both scripts are fully automated — they install packages, generate SSH keys, harden permissions, and configure everything.

### 3. Connect and go

```bash
ssh hunt
```

First time it'll ask you to confirm the host key. After that, you're in. That's it.

---

## How I Actually Use This

### Starting a hunt session
```bash
ssh hunt
tmux a -t hunt
opencode
```

### Getting back after my connection drops
Just run `ssh hunt` again. It reattaches to the same tmux session. Everything is still there.

### Copying things between phone and server
```bash
# Phone → server:
termux-clipboard-get | ssh hunt "cat > ~/clipboard-in"

# Server → phone (just pipe through SSH):
echo "target.com" | ssh hunt "cat"
```

There's also `scripts/sync-clipboard.sh` if you want it automated with polling.

---

## Scripts Explained

### `connect.sh`
SSH wrapper that retries 3 times if the connection drops, carries your phone clipboard content, and reattaches to your tmux session.

### `sync-clipboard.sh`
Watches a file on the server and syncs clipboard between your phone and server. Useful when you find a target URL on your phone and want it on your server instantly.

### `tmux-session.sh`
Opens a tmux workspace with three panes:

```
┌──────────────────────────────────────┐
│  opencode session                    │
│  ~/hunt/ workspace                   │
├──────────────────┬───────────────────┤
│  Terminal        │  htop / monitor   │
│  (run your tools)│  (keep an eye on  │
│                  │   resources)      │
└──────────────────┴───────────────────┘
```

---

## Verified On

This has been tested and works on:

- **Server:** Ubuntu 24.04 LTS (should work on 22.04+, Debian 11+)
- **Phone:** Termux v0.118 (F-Droid build), Android 14
- **Tailscale:** v1.76+
- **SSH:** OpenSSH 9.x on both sides

If something breaks on your setup, open an issue or — better — send a PR.

---

## Dry-Run Mode

Both setup scripts support `--dry-run` to preview changes without applying them:

```bash
bash setup/server-setup.sh --dry-run
bash setup/termux-setup.sh --dry-run
```

This shows every file that would be modified, every package that would be installed, and every config that would be changed. No surprises.

---

## Security Stuff I Set Up

| What | Why |
|---|---|
| `PasswordAuthentication no` | Nobody's guessing a password on your SSH |
| `PermitRootLogin no` | You shouldn't be root, ever |
| `~/.ssh/` permissions 700 | SSH will refuse keys if permissions are loose |
| Tailscale ACLs | You control exactly who can reach your server |
| UFW | Only Tailscale subnet can reach SSH |
| Fail2ban | Blocks anyone who fails auth 3 times |

Check `config/tailscale-hardening.md` for Tailscale ACL rules and extra kernel hardening.

---

## opencode Integration

The server script adds an alias so you can jump straight into opencode:

```bash
alias hunt-oc='ssh -t hunt "tmux new-session -A -s opencode \"cd ~/hunt && opencode\""'
```

It checks Tailscale connectivity, opens/reattaches a tmux session, launches opencode in `~/hunt/`, and logs everything to `~/hunt/session.log`.

---

## Things That Can Go Wrong (And How To Fix Them)

| Problem | Fix |
|---|---|
| `ssh hunt` just hangs | Tailscale isn't connected on one of the devices |
| `REMOTE HOST IDENTIFICATION CHANGED` | `ssh-keygen -R <TAILSCALE_IP>` |
| Permission denied (publickey) | Run `chmod 600 ~/.ssh/authorized_keys` on the server |
| tmux session not found | First time? Run `tmux new-session -s hunt` to create it |
| Clipboard not syncing | Install termux-api: `pkg install termux-api` |

---

## Why Tailscale?

| Method | Open Ports | Works Behind NAT? | Speed | Setup Pain |
|---|---|---|---|---|
| **Tailscale** | **0** | ✅ | Fast | Easy |
| WireGuard (manual) | 1 (UDP) | ❌ needs public IP | Fast | Medium |
| ngrok / bore | 0 | ✅ | Slow | Easy |
| Port forwarding | 1+ | ❌ | Fast | Easy but risky |
| ZeroTier | 0 | ✅ | Fast | Medium |

I went with Tailscale because it just works — no public IP needed, no ports open, and it's fast enough for SSH and terminal work.

---

## License

MIT. Take it, break it, make it better.
