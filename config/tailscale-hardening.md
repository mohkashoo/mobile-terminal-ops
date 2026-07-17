# Tailscale Hardening Guide

## Restrict SSH Access with Tailscale ACLs

Tailscale ACLs let you control exactly which devices can reach which ports on your server — even within the mesh.

### 1. Basic ACL (only your phone can SSH)

Create or edit your [ACL policy](https://login.tailscale.com/admin/acls):

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
    "tag:phone": ["kashoobest-droid@github"],
    "tag:server": ["kashoobest-droid@github"]
  }
}
```

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
