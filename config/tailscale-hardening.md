# Tailscale Hardening Guide

First-class hardening for the "Tailscale compromised" and "phone lost" rows of
the threat model. **Run `bash setup/tailscale-hardening.sh` on the server** —
it walks you through all three steps. This file is the reference / checklist.

## Checklist

| # | Control | Why | Done |
|---|---------|-----|------|
| 1 | 2FA on the Tailscale account | A stolen Tailscale login can't add devices / change ACLs without the TOTP | ☐ |
| 2 | Tailnet Lock (node-signing) | A compromised control plane or rogue node can't join the tailnet without a trusted signature | ☐ |
| 3 | SSH-only ACL (phone → server:22) | Even a fully compromised phone can only reach the server's SSH port, not the rest of the tailnet | ☐ |
| 4 | UFW Tailscale-only SSH (server-setup.sh) | Defense in depth below the VPN layer | ☐ |
| 5 | Strong phone lock + key passphrase | The endpoint that holds the keys | ☐ |

## 1. Two-factor authentication

This must be done in the admin console — there is no CLI for it:

1. Go to https://login.tailscale.com/admin/settings
2. Enable 2FA (TOTP app).
3. From now on, the admin console requires it.

**Why it matters:** without 2FA, a leaked Tailscale login (phishing, reused
password) lets an attacker into the admin console where ACLs, devices, and
key settings live. With 2FA, that single credential is not enough.

## 2. Tailnet Lock

Tailnet Lock cryptographically signs nodes into the tailnet. Even if the
Tailscale coordination server (or an admin) is compromised, a new device
cannot join without a signature from a trusted lock key.

```bash
# On the server (the trust anchor):
sudo tailscale lock init
# → prints a node key. Then sign the phone:
sudo tailscale lock add-key <phone-node-key>   # get it via `tailscale lock status` on the phone

# Verify:
tailscale lock status
```

Keep the lock key (and its back-up / key-holder list) safe. Losing it means
you can't add new devices.

**Why it matters:** this is the real answer to "what if Tailscale itself is
compromised". A compromised coordination server can't mint new devices into
your tailnet without your signature.

## 3. Restrict SSH Access with Tailscale ACLs

Tailscale ACLs let you control exactly which devices can reach which ports on
your server — even within the mesh. The phone is allowed SSH only; the server
can reach the tailnet normally.

### 1. ACL (only your phone can SSH, port 22 only)

Create or edit your [ACL policy](https://login.tailscale.com/admin/acls).
The hardening script writes `config/tailscale-acl.json` with your real
tailnet identity **auto-detected** (via `tailscale status --json`) — no
placeholder to forget. If detection fails it prompts you. Example:

```json
{
  "acls": [
    {
      "action": "accept",
      "src":    ["tag:phone"],
      "dst":    ["tag:server:22"]
    },
    {
      "action": "accept",
      "src":    ["tag:server"],
      "dst":    ["*:*"]
    }
  ],
  "tagOwners": {
    "tag:phone":  ["you@github.com"],
    "tag:server": ["you@github.com"]
  }
}
```

`tagOwners` must contain your **actual** tailnet login (what the script wrote
into `config/tailscale-acl.json`). Verify before pasting: `tailscale status`
shows your login name.

### 2. Add tags via CLI

```bash
# On server
sudo tailscale set --advertise-tags=tag:server

# On phone (Termux)
tailscale set --advertise-tags=tag:phone
```

### 3. Verify ACLs

```bash
tailscale status
tailscale ping 100.x.x.x
```

## Additional Server Hardening

### Disable ICMP ping (optional)
```bash
echo "net.ipv4.icmp_echo_ignore_all=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Enable UFW (already done by server-setup.sh)
```bash
sudo ufw status verbose
```

### Kernel hardening (sysctl)
```bash
cat >> /etc/sysctl.d/99-hardening.conf << 'SYS'
net.ipv4.tcp_syncookies=1
net.ipv4.ip_forward=0
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.accept_source_route=0
kernel.exec-shield=1
kernel.randomize_va_space=2
SYS
sudo sysctl --system
```

### Auditd (track SSH logins)
```bash
sudo apt install auditd -y
sudo auditctl -w /var/log/auth.log -p wa -k auth_logs
```