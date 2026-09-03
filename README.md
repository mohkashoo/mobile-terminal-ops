<p align="center">
  <img src="https://github.com/mohkashoo/mobile-terminal-ops/raw/master/.github/social-preview.png" alt="Mobile Terminal Ops">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/version-v2.0.0-blue" alt="Version 2.0.0">
  <img src="https://img.shields.io/badge/tested-Ubuntu%2024.04%20%7C%20macOS%2015%20%7C%20Termux%20%7C%20iSH%20%7C%20Blink-brightgreen" alt="Tested On">
  <img src="https://img.shields.io/badge/ci-passing-brightgreen" alt="CI">
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
| **Phone is lost/stolen** | Someone has your SSH key and can reach your server via Tailscale | SSH keys are **passphrase-protected by default** (the setup scripts refuse unencrypted keys without `--no-passphrase --i-understand-the-risk`). Revoke the key on the server (`~/.ssh/authorized_keys`), de-auth the device in Tailscale admin, and rely on the **auto-lock dead-man's switch** (below) so the key dies even if you don't act. |
| **Phone has malware** | Attacker can SSH into your server | Strong screen lock. Don't root/jailbreak. Passphrase on the SSH key is **required**. Never carry secrets through clipboard sync (see below). |
| **Tailscale compromised** | Someone controls the coordination server | Tailscale is open-source, end-to-end encrypted; WireGuard keys never leave your devices. **First-class hardening** (`setup/tailscale-hardening.sh`): 2FA on the account, **Tailnet Lock** (node-signing — a compromised control plane can't mint new devices without your signature), and an **SSH-only ACL** (phone can reach server on port 22 only, not the whole tailnet). |
| **Server compromised** | Someone breaks in through another service | UFW (Linux) limits access to Tailscale subnet only. fail2ban rate-limits auth. No other public services. |
| **Key rotation** | You want to swap keys | Add the new key to `authorized_keys`, remove the old one. No need to re-run setup. |
| **Email leakage** | A third-party mail provider sees live findings | Default delivery is your **local MTA** — data never leaves your infrastructure. SMTP is **opt-in** (`EMAIL_SMTP_OK="yes"`), bodies are **redacted by default**, and `EMAIL_ENCRYPT` (gpg/age) encrypts the full content. |
| **Clipboard sync** | A password/token copied through the sync tunnel lands plaintext on the server | Clipboard carry is **opt-in** (`--clipboard` / `sync-clipboard.sh` requires an explicit acknowledgment) and prints a warning on every run. Never copy secrets through it. |

**Bottom line:** phone lost → the dead-man's switch revokes the key on its own within 24h, Tailnet Lock blocks rogue nodes, and the ACL limits the phone to SSH. Phone malware → the passphrase keeps the key unusable without your screen unlock. Don't bet the whole chain on one layer.

### Bug-bounty scope disclaimer

This tool is not a substitute for program-specific data handling requirements.
If you route findings through email or third-party clipboard sync, **check your
bounty program's confidentiality terms first** — some programs forbid findings
leaving your test environment, and a summary email to your own address is still
data leaving your workstation. When in doubt, use the local relay + encryption
(above) and keep clipboard sync off.

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
| Key-only auth | ED25519 keys, passwords disabled, **passphrase required** |
| Persistent sessions | tmux saves your workspace across disconnects |
| opencode integration | One alias launches opencode in your hunt dir |
| Clipboard sync | Opt-in only (`--clipboard`); warns on every run — never copy secrets through it |
| One-tap connect | `ssh hunt` — that's it |
| Auto-reconnect | Connection drops? Retries 3 times |
| Dead-man's switch | No phone heartbeat for 24h → key auto-revoked (optional) |
| Short-lived keys | SSH CA certs expire in 48h even if you never revoke (optional) |
| Tools ready | nuclei, ffuf, gf, naabu — whatever you use |

---

## Project Layout

```
mobile-terminal-ops/
├── README.md
├── setup/
│   ├── server-setup.sh         # Run on Ubuntu or macOS server
│   ├── termux-setup.sh         # Run on Android (Termux)
│   ├── iphone-ish.sh           # Run on iPhone (iSH app)
│   ├── iphone-blink.md         # Manual setup for Blink Shell (iPhone)
│   ├── tailscale-hardening.sh  # 2FA + Tailnet Lock + SSH-only ACL (first-class)
│   ├── install-auto-lock.sh    # Dead-man's switch (heartbeat → auto-revoke)
│   └── install-ssh-ca.sh       # Short-lived phone certs via local SSH CA
├── scripts/
│   ├── connect.sh              # Smart reconnect wrapper (clipboard opt-in)
│   ├── sync-clipboard.sh       # Clipboard bridge (acknowledgment gated)
│   ├── tmux-session.sh         # 3-pane tmux layout
│   ├── email-summary.sh        # Redacted, optionally encrypted email sender
│   ├── watch-session.sh        # Watch tmux pane → email summaries
│   ├── heartbeat.sh            # Phone-side heartbeat (manual)
│   ├── auto-lock-server.sh     # Revoke phone key after idle timeout
│   └── sign-phone-key.sh       # Sign phone key into a 48h cert
├── config/
│   ├── ssh-config              # SSH config template
│   ├── email-config.example    # Email settings template (SMTP opt-in)
│   └── tailscale-hardening.md  # Tailscale hardening reference + ACL
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

> **Passphrase:** both setup scripts require a passphrase when generating your
> SSH key. That's deliberate — a stolen phone with an unencrypted key is a
> stolen server. (Escaping it requires `--no-passphrase --i-understand-the-risk`.)

### Step 8: Harden (10 minutes, worth it)

```bash
# On the server — 2FA, Tailnet Lock, SSH-only ACL
bash setup/tailscale-hardening.sh

# On the server — dead-man's switch: no phone heartbeat for 24h → key auto-revoked
bash setup/install-auto-lock.sh

# Optional, recommended — short-lived phone certs (48h, auto-expire)
bash setup/install-ssh-ca.sh
bash scripts/sign-phone-key.sh
```

Each step is confirm-driven with `--dry-run` support, so you can preview everything first.

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
# Phone → server (manual, opt-in):
termux-clipboard-get | ssh hunt "cat > ~/clipboard-in"

# Server → phone (pipe through SSH):
echo "target.com" | ssh hunt "cat"
```

> **Clipboard = plaintext on the server.** `connect.sh --clipboard` and
> `scripts/sync-clipboard.sh` are opt-in and print a warning on every run
> (`sync-clipboard.sh` also requires a one-time acknowledgment). Never copy
> passwords, API keys, tokens, or private keys through clipboard sync —
> anything you copy can leak to the server's filesystem and any process that
> can read your user's files.

---

## Email Summaries — Every Opencode Response in Your Inbox

**The problem:** You disconnect from SSH (train, dead wifi). opencode finishes a scan or finds something. You have no idea until you reconnect.

**The fix:** `watch-session.sh` watches your opencode pane and emails a styled summary for every response.

### What triggers an email

| Trigger | When |
|---|---|
| **New output** | Every time the pane content changes (debounced 15s) |
| **Watcher started** | When you launch the watcher |
| **Session stalled** | 120s of no output — opencode is waiting for you |
| **Session ended** | tmux pane or session dies |

### How it works

```
tmux pane → watch-session.sh (polls every 4s)
                │
                ├─ output changed? → email-summary.sh ──→ Styled HTML email
                ├─ frozen?         → email-summary.sh ──→ "Stalled" alert
                └─ pane gone?      → email-summary.sh ──→ "Session ended"
```

Each email is formatted with a dark terminal theme, monospace font, timestamp, and session context — readable on any phone's email app.

### Setup (2 minutes)

1. **Configure email delivery:**

```bash
cd mobile-terminal-ops
cp config/email-config.example config/email-config
nano config/email-config
```

Set `EMAIL_TO` to your email address. **Default delivery is your server's own
local mail relay** (`sendmail` / `mail`) — opencode output never has to leave
your infrastructure. SMTP (Gmail, Outlook) is **opt-in**: fill in
`SMTP_URL`/`SMTP_USER`/`SMTP_PASS` **and** set `EMAIL_SMTP_OK="yes"` to confirm
you understand a third party now transports your summaries.

2. **Test it:**

```bash
echo "Test output from opencode" | bash scripts/email-summary.sh --to you@example.com --subject "Test"
```

3. **Launch with email summaries:**

```bash
bash scripts/watch-session.sh --target /hunt/paypal:0.0 --poll 4
```

### Security: redaction + encryption

- **Redact-by-default.** Every email body is scrubbed of likely secrets before
  sending — private-key blocks, `Authorization:`/`Bearer` lines, and common
  token formats (`sk-`, `ghp_`, `xox`, AWS keys, JWTs, ...). Add your own
  patterns via `EMAIL_REDACT_EXTRA` in `config/email-config`.
- **Encrypt before any SMTP.** Set `EMAIL_ENCRYPT="gpg"` (or `"age"`) plus a
  recipient in `config/email-config`. The full content is attached encrypted
  (`summary.gpg.asc` / `summary.age`) — decrypt on your phone with `gpg -d` or
  `age -d` — while the email body only carries a redacted preview. **If you use
  SMTP at all, use this.**

### Delivery methods (auto-detected)

| Method | Config | Notes |
|---|---|---|
| **Local sendmail** (default) | (none) | Postfix/other MTA on your server. Data stays yours. |
| **mail command** | (none) | Local delivery fallback |
| **curl SMTP** (opt-in) | `SMTP_URL`, `SMTP_USER`, `SMTP_PASS`, **`EMAIL_SMTP_OK="yes"`** | Gmail/Outlook/any SMTP. Third-party sees (or transports) the payload. |

If none of these work, the email is saved to `email-queue/` in the project directory.

### Tuning

Edit `config/email-config`:

| Variable | Default | What it does |
|---|---|---|
| `POLL_INTERVAL` | `4` | Seconds between pane checks |
| `STALL_TIMEOUT` | `120` | Seconds of silence before "stalled" alert |
| `OUTPUT_COOLDOWN` | `15` | Minimum seconds between emails |

---

## Scripts Explained

### `setup/server-setup.sh`
Detects your OS (Linux or macOS), installs packages via `apt` or `brew`, sets up SSH keys, hardens config, configures UFW (Linux) or skips it (macOS). Adds `TrustedUserCAKeys` if an SSH CA exists. Supports `--dry-run` and `--force`.

### `setup/termux-setup.sh`
For Android (Termux). Installs packages, generates SSH key (**passphrase required** unless `--no-passphrase --i-understand-the-risk`), writes SSH config with connection multiplexing, adds aliases to bashrc. Supports `--dry-run` and `--force`.

### `setup/tailscale-hardening.sh`
First-class Tailscale hardening: 2FA on the account (admin console), **Tailnet Lock** via `tailscale lock init`, and an **SSH-only ACL** (phone→server:22). Writes the ACL template to `config/tailscale-acl.json`. See `config/tailscale-hardening.md`.

### `setup/install-auto-lock.sh`
Installs the dead-man's switch: `~/.ssh/rc` updates a heartbeat on every Tailscale SSH login, and a **system-level systemd timer** (survives reboots with no login session) — or cron — runs `scripts/auto-lock-server.sh` hourly. No heartbeat for 24h → the phone key is revoked from `authorized_keys` automatically. Run `scripts/auto-lock-server.sh --check-health` to verify the watchdog itself is alive.

### `setup/install-ssh-ca.sh`
Creates a local SSH CA (verified non-empty-passphrase) and tells sshd to trust it (`TrustedUserCAKeys`, verified via `sshd -T`). Lets you sign the phone's key into **short-lived certificates** instead of permanent access.

### `setup/iphone-ish.sh`
For iPhone (iSH app — Alpine Linux). Same idea as Termux but adapted for `apk` package manager. **Passphrase required** on the SSH key.
iSH can't run in the background — the connection stays alive only while iSH is open.

### `setup/iphone-blink.md`
Manual guide for Blink Shell (paid iPhone app). More reliable than iSH — supports mosh, background connections, hardware keyboards.

### `scripts/connect.sh`
SSH wrapper that retries 3 times, reattaches to tmux, and **optionally** carries your clipboard (`--clipboard`, off by default — prints a warning when used). Runs on Termux.

### `scripts/sync-clipboard.sh`
Bidirectional clipboard sync (push/pull/watch). Prints a plaintext-on-server warning **on every run** and requires a one-time acknowledgment. Opt-in module.

### `scripts/heartbeat.sh`
Phone-side helper that pokes the server's dead-man's-switch heartbeat (`--check` shows the last heartbeat). Automatic heartbeats happen on every SSH login via `~/.ssh/rc`.

### `scripts/auto-lock-server.sh`
The dead-man's switch itself: if the phone heartbeat is older than `MAX_IDLE_HOURS` (default 24) — or missing, unreadable, or future-dated — it removes the phone key from `~/.ssh/authorized_keys`. Fails closed on any ambiguity. `--check-health` reports whether the timer/cron is actually firing. Run by `setup/install-auto-lock.sh`.

### `scripts/sign-phone-key.sh`
Signs the phone's public key into a certificate valid for `--hours` (default 48). Installs the cert in `authorized_keys` (appended before the old raw key is removed by its key blob), prints the cert to save on the phone as `~/.ssh/id_ed25519-cert.pub`. When it expires, access is gone — re-sign to renew.

### `scripts/email-summary.sh`
Reads opencode output from stdin and sends a styled HTML email to your configured address. **Redacts secrets by default**, supports gpg/age encryption of the full content, and refuses third-party SMTP unless `EMAIL_SMTP_OK="yes"`. Default transport is the local MTA. Standalone: `echo "output" | bash scripts/email-summary.sh --to you@example.com --subject "Summary"`.

### `scripts/watch-session.sh`
Watches a tmux pane and emails styled summaries for every opencode response. Detects output changes (forwards immediately), stalls (120s of silence), and session crashes. Reads `config/email-config`.

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
| **Passphrase-protected SSH key (required)** | A stolen phone can't use the key without your passphrase |
| **Tailscale 2FA + Tailnet Lock + SSH-only ACL** | Compromised Tailscale account/control plane can't add devices or reach your server beyond port 22 |
| **Email: local relay by default, SMTP opt-in** | Findings stay on your infrastructure unless you explicitly allow a third party |
| **Email redact-by-default + optional encryption** | No live credentials in your inbox; full content only ever travels encrypted |
| **Clipboard sync opt-in with warnings** | No silent expansion of attack surface; secrets stay out of the plaintext tunnel |
| **Dead-man's switch (optional)** | Lost phone → key auto-revoked after 24h of no heartbeat |
| **Short-lived certs via SSH CA (optional)** | Lost phone → credential expires on its own in 48h |
| Tailscale ACLs | Control who reaches your server |
| UFW (Linux) | Only Tailscale subnet can reach SSH |
| Fail2ban | 3 failed attempts = 24h ban |

Check `config/tailscale-hardening.md` for the full Tailscale hardening reference.

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

## Threat Model Tested

Claims should be tested, not asserted. Below is the walkthrough I run against my
own setup (and you should run against yours) to verify the security model. Fill
in the Result column with your measured outcome.

| Scenario | How I simulate it | What "pass" looks like | Result |
|---|---|---|---|
| **Phone stolen** | Remove my phone from my pocket… and stop touching it for 25h | `auto-lock-server.sh` revokes the phone key on its own; `ssh` from the phone fails with permission denied | ☐ |
| **Key revocation speed** | Run `scripts/auto-lock-server.sh` manually with `MAX_IDLE_HOURS=0` | Phone key gone from `authorized_keys` in < 2 minutes | ☐ |
| **Tailscale account compromised** | Sign out all devices; try to add a rogue node | Without 2FA code it can't re-auth; Tailnet Lock requires a trusted signature before the rogue node joins | ☐ |
| **Tailnet Lock blocks rogue node** | Spin up a throwaway device, `tailscale up`, attempt to join the tailnet | Join fails until a trusted lock key signs it | ☐ |
| **ACL restricts phone** | From the phone, `nc <server-ip> 443` and `nc <server-ip> 22` | 443 is blocked by ACL, 22 is allowed | ☐ |
| **Passphrase protects a lost key** | `ssh-keygen -y -P '' -f ~/.ssh/id_ed25519` on the phone | Command fails — the key has a passphrase | ☐ |
| **Email redaction** | Pipe output containing `Authorization: Bearer xyz…` into `email-summary.sh` | Email shows `[REDACTED]`, not the token | ☐ |
| **Email encryption** | `EMAIL_ENCRYPT="gpg"`, send, decrypt attachment on the phone | Full content decrypts with the phone's private key only | ☐ |

**If you run any of these and the "pass" column doesn't hold — that's a bug.
Open an issue so it gets fixed.**

### Watchdog health — how you'd notice the dead-man's switch died

A dead-man's switch that silently stops functioning is worse than none,
because it creates false confidence. The auto-lock is designed to fail
**closed** (missing/stale/unreadable heartbeat → revoke), but nothing it
controls can catch the scheduler itself never running. Check on it:

```bash
# One-liner that exits non-zero if the watchdog is dead or stale:
~/.local/bin/mto-auto-lock.sh --check-health

# What it reports:
#   - last watchdog run timestamp (auto-lock-last-run) and whether it's stale
#   - the systemd timer status (systemctl status mto-autolock.timer)
#   - the cron entry, if any

# Manual verification:
systemctl status mto-autolock.timer     # system-level timer (runs headless)
crontab -l | grep mto-auto-lock          # cron fallback
ls -la ~/.local/share/mobile-terminal-ops/auto-lock.log   # log freshness
```

Things that kill the watchdog and how to catch them:

| Failure | How you notice |
|---|---|
| Timer disabled after reboot / after a crash | `--check-health` shows "last run is older than MAX_IDLE_HOURS" |
| `~/.ssh/rc` removed or rejected | heartbeats stop → the switch correctly fires and revokes the key (fail closed) — you'll see it on next connect |
| Disk full / log unwritable | `auto-lock.log` stops growing; `--check-health` still reports last run |
| Cron entry lost | `--check-health` shows no timer AND no cron line |
| System clock jumped forward | a future-dated heartbeat is treated as stale → key revoked (fail closed) |

The **first-run footgun**: the switch arms the moment you install it. If the
phone does not SSH in within `MAX_IDLE_HOURS` of arming, the key is revoked.
Log in once right after installing to set the heartbeat.

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
