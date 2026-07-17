# iPhone Setup with Blink Shell

[Blink Shell](https://blink.sh) is a paid terminal emulator for iOS ($20-ish) that's more reliable than iSH for SSH work. It supports background connections, mosh, tmux, and hardware keys.

## Setup Steps

### 1. Install Blink Shell from the App Store

### 2. Generate an SSH Key inside Blink

Open Blink and run:

```bash
ssh-keygen -t ed25519 -C "iphone-blink"
```

The key is stored in Blink's internal storage at `~/.ssh/id_ed25519.pub`.

### 3. Copy Your Public Key

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the output (starts with `ssh-ed25519`).

### 4. Add the Key to Your Server

On your server run:

```bash
echo "<paste the key here>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 5. Configure Blink Host

In Blink, create a host config:

```bash
config
```

Then add:

```
host hunt
    hostname 100.68.188.37
    user kashoo
    port 22
```

Replace the IP with your server's Tailscale IP, and the user with your server username.

### 6. Connect

```bash
ssh hunt
```

## Pro Tips for Blink

- **Mosh** (mobile-shell) handles network drops better than SSH on mobile. Install on server: `sudo apt install mosh`. Connect: `mosh hunt`.
- **Tmux** + Blink works great — sessions survive app backgrounding.
- **Clipboard** sync: Blink shares the iOS clipboard. You can copy from Safari and paste into the SSH session.
- **Hardware keyboards** are fully supported (Magic Keyboard, etc.).
- **Local echo** settings can be tweaked in Blink's config for laggy connections.

## Limitations vs Termux

| Feature | Blink Shell | Termux (Android) |
|---|---|---|
| Background SSH | ✅ (mosh) | ✅ |
| Clipboard API | ❌ (iOS clipboard only) | ✅ (termux-clipboard) |
| Local scripts | ❌ (SSH client only) | ✅ (can run tools locally) |
| Price | ~$20 | Free |
| App Store | Yes | No (F-Droid) |
