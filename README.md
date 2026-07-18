<p align="center">
  <img src="https://github.com/mohkashoo/mobile-terminal-ops/raw/master/.github/social-preview.png" alt="Mobile Terminal Ops">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/tested-Ubuntu%2024.04%20%7C%20macOS%2015%20%7C%20Termux%20%7C%20iSH%20%7C%20Blink-brightgreen" alt="Tested On">
  <img src="https://img.shields.io/badge/shell-bash-lightgrey" alt="Shell">
</p>

# Mobile Terminal Ops

**Your phone becomes a full remote hacking workstation. Zero open ports. Persistent tmux. opencode ready. One-tap reconnect.**

<p align="center">
  <img src="https://github.com/mohkashoo/mobile-terminal-ops/raw/master/assets/demo.gif" alt="Demo — Termux SSH into server, launching opencode + naabu port scan">
  <br>
  <em>Android (Termux) → SSH → Ubuntu server → opencode running naabu</em>
</p>

```
Phone ──[Tailscale/WireGuard]──> Server (Ubuntu / macOS)
 │                                    │
 ├─ ssh key (ED25519)                 ├─ tmux + opencode
 ├─ clipboard sync                    ├─ persistent sessions
 └─ one-tap reconnect                 └─ bug hunting toolchain
```

---

## Security Model & Known Risks

This setup is secure **as long as your phone is secure**. Here's the honest threat model:

| Scenario | Risk | How I Handle It |
|---|---|---|
| **Phone is lost/stolen** | Someone has your SSH key and can reach your server via Tailscale | Revoke the key immediately on the server (remove it from `~/.ssh/authorized_keys`). Then de-authorize the device in Tailscale admin. |
| **Phone has malware** | Attacker can SSH into your server | Use a strong screen lock. Don't root/jailbreak. Consider a passphrase on your SSH key (`ssh-keygen -p -f ~/.ssh/id_ed25519`). |
| **Tailscale compromised** | Someone controls the coordination server | Tailscale is open-source, end-to-end encrypted. WireGuard keys never leave your devices. Still — don't bet everything on one layer. |
| **Server compromised** | Someone breaks in through another service | UFW (Linux) limits access to Tailscale subnet only. fail2ban rate-limits auth. No other public services. |
| **Key rotation** | You want to swap keys | Add the new key to `authorized_keys`, remove the old one. No need to re-run setup. |

**Bottom line:** If your phone is lost, act fast — remove the key and de-auth from Tailscale. If you're paranoid, add a passphrase to your SSH key.

---

## Why?

Every hunter I know either rents a VPS or opens port 22 on their home router. Both suck.

- VPS costs money and your tools aren't there
- Opening port 22 means Shodan, masscan, and every bot knows your IP

This setup uses **Tailscale** — a WireGuard mesh VPN. Your server has **zero exposed ports**. It's invisible to the internet. You connect from your phone through an encrypted tunnel that only your devices can use.

Add **tmux persistence**, **opencode**, and **clipboard sync**, and you can disconnect mid-hunt, go outside, reconnect from your phone, and pick up **exactly** where you left off.

---

## What You're Getting

| Feature | How It Works |
|---|---|
| Zero open ports | Tailscale mesh VPN — no port forwarding |
| Key-only auth | ED25519 keys, passwords disabled |
| Persistent sessions | tmux saves your workspace across disconnects |
| opencode integration | One alias launches opencode in your hunt dir |
| Clipboard sync | Copy on phone → paste on server (and back) |
| One-tap connect | `ssh hunt` — that's it |
| Auto-reconnect | Connection drops? Retries 3 times |
| Tools ready | nuclei, ffuf, gf, naabu — whatever you use |

---

## Project Layout

```
mobile-terminal-ops/
├── README.md
├── setup/
│   ├── server-setup.sh       # Run on Ubuntu or macOS server
│   ├── termux-setup.sh       # Run on Android (Termux)
│   ├── iphone-ish.sh         # Run on iPhone (iSH app)
│   └── iphone-blink.md       # Manual setup for Blink Shell (iPhone)
├── scripts/
│   ├── connect.sh            # Smart reconnect wrapper
│   ├── sync-clipboard.sh     # Clipboard bridge
│   ├── tmux-session.sh       # 3-pane tmux layout
│   ├── notify.sh             # Push alerts to phone (ntfy/Pushover)
│   └── watch-session.sh      # Watch tmux pane for stalls/keywords
├── config/
│   ├── ssh-config            # SSH config template
│   ├── notify-config.example # Notification settings template
│   └── tailscale-hardening.md
└── .gitignore
```

---

## Quick Start (7 Minutes)

### Step 1: Install Tailscale on both devices

```bash
# On your server (Ubuntu or macOS)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# On your phone — install from Google Play (Android) or App Store (iPhone)
# Log into the same Tailscale account on both
```

After that, run `tailscale ip -4` on your server and write down the IP. It'll look like `100.x.x.x`. You'll also need your server **username** — run `whoami` to get it.

### Step 2: Enable SSH on your server

**Ubuntu:** SSH is usually running already. Check with `systemctl status sshd`.

**macOS:** Go to System Settings → General → Sharing → turn on **Remote Login**. Or run:
```bash
sudo systemsetup -setremotelogin on
```

### Step 3: Set up your phone

**Android (Termux):**
```bash
pkg install git -y
git clone https://github.com/mohkashoo/mobile-terminal-ops.git
cd mobile-terminal-ops
bash setup/termux-setup.sh
```

**iPhone (iSH — free):**
```bash
apk add git
git clone https://github.com/mohkashoo/mobile-terminal-ops.git
cd mobile-terminal-ops
sh setup/iphone-ish.sh
```

**iPhone (Blink Shell — paid, better):**
Follow the manual guide at `setup/iphone-blink.md`. Generate a key with `ssh-keygen -t ed25519`, then configure a host entry.

### Step 4: Copy your public key

After the phone script finishes, grab your key:

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the output. It starts with `ssh-ed25519` and ends with your device name.

### Step 5: Run the server setup script

Now on your server:
```bash
git clone https://github.com/mohkashoo/mobile-terminal-ops.git
cd mobile-terminal-ops
bash setup/server-setup.sh
```

When it asks for your public key, paste the one you copied from your phone and press Ctrl+D.

### Step 6: Set the Tailscale IP on your phone

Edit `~/.ssh/config` on your phone and change the `HostName` line to your server's Tailscale IP:

```
Host hunt
    HostName 100.x.x.x       # ← change this to your server's Tailscale IP
    User your-server-username
```

### Step 7: Connect

```bash
ssh hunt
```

First time it'll ask you to confirm the host key. After that, you're in.

---

## How I Actually Use This

### Starting a hunt
```bash
ssh hunt           # connect
tmux a -t hunt    # attach to session
opencode          # fire up opencode
```

### Reconnecting after a drop
Just `ssh hunt` again. It reattaches to the same tmux session. Everything's still there.

### Copying between phone and server
```bash
# Phone → server:
termux-clipboard-get | ssh hunt "cat > ~/clipboard-in"

# Server → phone (pipe through SSH):
echo "target.com" | ssh hunt "cat"
```

See `scripts/sync-clipboard.sh` if you want automated clipboard polling.

---

## Notifications — Telegram Alerts

**The problem:** You disconnect from your SSH session (train, dead wifi, whatever). opencode finds something interesting or gets stuck waiting for you. You have no idea until you manually reconnect and check.

**The fix:** `watch-session.sh` runs on the server alongside tmux. It watches your opencode pane and pushes a notification to your phone when something happens.

### Two modes

| Mode | `NOTIFY_MODE` | Behavior |
|---|---|---|
| **Forward all output** (default) | `all` | Every new line from opencode is sent to Telegram in real time — you read the hunt on your phone |
| **Keyword-only** | `keyword` | Only alerts on pattern matches (CRITICAL, BUG, ERROR, etc.) and stall/session events |

**Recommended:** `all`. You'll see every opencode response on your phone as it happens. The 5-second cooldown prevents spam during rapid output.

### What triggers an alert

| Trigger | Mode | Threshold |
|---|---|---|
| **New output** | `all` | Every poll where output changes (debounced 5s) |
| **Stalled output** | both | 120s of no output change |
| **Session ended** | both | Immediate |
| **Keyword match** | `keyword` | Configurable regex |

### How it works

```
tmux pane → watch-session.sh (polls every 4s)
                │
                ├─ all mode ──→ diff new lines → notify.sh ──→ Your phone
                │
                ├─ keyword mode ──→ match regex → notify.sh ──→ Your phone
                ├─ Output frozen? → count seconds → alert on stall
                └─ Pane gone?     → alert immediately
                │
                ▼
         notify.sh ──→ Telegram (recommended)
                           │
                           ▼
                    Your phone buzzes
```

### Setup — Telegram (recommended, 3 minutes)

1. **Create a Telegram bot:**
   - Open Telegram, search for `@BotFather`
   - Send `/newbot`, pick a name (e.g. `hunt-bot`)
   - Save the bot token it gives you (looks like `123456:ABCdef...`)

2. **Get your chat ID:**
   - Start a chat with your new bot, send any message
   - Run this (replace TOKEN with yours):
     ```bash
     curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq .result[0].message.chat.id
     ```
   - Save the number it returns

3. **Configure on your server:**

```bash
cd mobile-terminal-ops
cp config/notify-config.example config/notify-config
nano config/notify-config
# Uncomment TG_BOT and TG_CHAT, paste your values
```

4. **Test it:**

```bash
bash scripts/notify.sh --telegram-bot <TOKEN> --telegram-chat <ID> "Test" "Phone should buzz" 4
```

5. **Launch with notifications:**

```bash
bash scripts/tmux-session.sh --notify
```

Disconnect from SSH. If opencode stalls or finds a keyword match, your Telegram bot messages you.

### Tuning

Edit `config/notify-config` on the server to adjust:

| Variable | Default | What it does |
|---|---|---|
| `NOTIFY_MODE` | `all` | `all` = forward every opencode response, `keyword` = only match patterns |
| `POLL_INTERVAL` | `4` | Seconds between pane checks (lower = faster alerts, higher = less CPU) |
| `STALL_TIMEOUT` | `120` | Seconds of silence before "stalled" alert |
| `COOLDOWN` | `5` | Minimum seconds between output alerts in `all` mode |
| `KEYWORDS` | (regex) | Pipe-separated patterns; only used in `keyword` mode |

### Other backends

| Backend | Config Fields | Notes |
|---|---|---|
| **Telegram** (recommended) | `TG_BOT`, `TG_CHAT` | Free, reliable, push notifications on both Android & iOS |
| Pushover | `PUSHOVER_USER`, `PUSHOVER_TOKEN` | $5 one-time, reliable |
| ntfy.sh | `NTFY_TOPIC` | Free, no account needed, can be flaky |

The backend priority is: Telegram > Pushover > ntfy. If Telegram is configured, it's used. If not, falls back to Pushover, then ntfy.

### Degrades gracefully

If `config/notify-config` doesn't exist or `NTFY_TOPIC` is empty, `watch-session.sh` skips silently. No alerts, no errors. Everything else still works.

---

## Scripts Explained

### `setup/server-setup.sh`
Detects your OS (Linux or macOS), installs packages via `apt` or `brew`, sets up SSH keys, hardens config, configures UFW (Linux) or skips it (macOS). Supports `--dry-run` and `--force`.

### `setup/termux-setup.sh`
For Android (Termux). Installs packages, generates SSH key, writes SSH config with connection multiplexing, adds aliases to bashrc. Supports `--dry-run` and `--force`.

### `setup/iphone-ish.sh`
For iPhone (iSH app — Alpine Linux). Same idea as Termux but adapted for `apk` package manager.
iSH can't run in the background — the connection stays alive only while iSH is open.

### `setup/iphone-blink.md`
Manual guide for Blink Shell (paid iPhone app). More reliable than iSH — supports mosh, background connections, hardware keyboards.

### `scripts/connect.sh`
SSH wrapper that retries 3 times, carries your clipboard, and reattaches to tmux. Runs on Termux.

### `scripts/sync-clipboard.sh`
Bidirectional clipboard sync. Pushes/pulls between phone and server via SSH.

### `scripts/notify.sh`
Sends push notifications to your phone via **Telegram** (recommended), Pushover, or ntfy.sh. Backend priority: Telegram > Pushover > ntfy. Call standalone: `bash notify.sh --telegram-bot TOKEN --telegram-chat ID "Title" "Message" 4`.

### `scripts/watch-session.sh`
Watches a tmux pane and pushes notifications to your phone. **Two modes:** `all` forwards every opencode response as it happens; `keyword` only alerts on pattern matches. Also detects stalls (120s of silence) and session crashes. Launched automatically by `tmux-session.sh --notify`. Reads `config/notify-config`.

### `scripts/tmux-session.sh`
Opens a tmux workspace with three panes. Pass `--notify` to also launch the notification watcher in the background.

```
┌──────────────────────────────────────┐
│  opencode session                    │
│  ~/hunt/ workspace                   │
├──────────────────┬───────────────────┤
│  Terminal        │  htop / monitor   │
│  (run tools)     │  (system watch)   │
└──────────────────┴───────────────────┘
```

---

## Dry-Run Mode

Both setup scripts support `--dry-run` to preview changes:

```bash
bash setup/server-setup.sh --dry-run
bash setup/termux-setup.sh --dry-run
```

Shows every file that would change, every package installed, every config modified. Zero surprises.

---

## Security Stuff I Set Up

| What | Why |
|---|---|
| `PasswordAuthentication no` | No password guessing |
| `PermitRootLogin no` | You don't need to be root |
| `~/.ssh/` permissions 700 | SSH refuses keys if permissions are loose |
| Tailscale ACLs | Control who reaches your server |
| UFW (Linux) | Only Tailscale subnet can reach SSH |
| Fail2ban | 3 failed attempts = 24h ban |

Check `config/tailscale-hardening.md` for ACL rules and kernel hardening.

---

## opencode Integration

The server script adds this alias so you jump straight into opencode:

```bash
alias hunt-oc='ssh -t hunt "tmux new-session -A -s opencode \"cd ~/hunt && opencode\""'
```

It connects, opens/reattaches tmux, launches opencode in `~/hunt/`, and logs everything.

---

## Verified On

| Device | OS | Works? |
|---|---|---|
| **Server** | Ubuntu 24.04 LTS | ✅ Tested |
| **Server** | macOS 15 (Sequoia) | ✅ Tested |
| **Phone** | Android 14 + Termux v0.118 | ✅ Tested |
| **Phone** | iPhone (iSH — Alpine Linux) | ✅ Works |
| **Phone** | iPhone (Blink Shell) | ✅ Works |
| **Tailscale** | v1.76+ | ✅ |
| **SSH** | OpenSSH 9.x | ✅ |

Something breaks? Open an issue. Better yet, send a PR.

---

## Things That Can Go Wrong

| Problem | Fix |
|---|---|
| `ssh hunt` hangs | Tailscale isn't connected on one side. Check both devices. |
| `REMOTE HOST IDENTIFICATION CHANGED` | `ssh-keygen -R <TAILSCALE_IP>` |
| Permission denied (publickey) | `chmod 600 ~/.ssh/authorized_keys` on the server |
| tmux not found | Install it: `sudo apt install tmux` or `brew install tmux` |
| tmux session not found | First time? Run `tmux new-session -s hunt` to create it |
| Clipboard not syncing (Termux) | `pkg install termux-api` |
| Homebrew not found (macOS) | Install: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| iSH can't stay connected | iSH can't run in background. Use Blink Shell instead. |

---

## Why Tailscale?

| Method | Open Ports | NAT Traversal | Speed | Setup Pain |
|---|---|---|---|---|
| **Tailscale** | **0** | ✅ | Fast | Easy |
| WireGuard (manual) | 1 (UDP) | ❌ needs public IP | Fast | Medium |
| ngrok / bore | 0 | ✅ | Slow | Easy |
| Port forwarding | 1+ | ❌ | Fast | Easy but risky |
| ZeroTier | 0 | ✅ | Fast | Medium |

I went with Tailscale because it just works — no public IP, no open ports, and fast enough for SSH.

---

## License

MIT. Take it, break it, make it better.
