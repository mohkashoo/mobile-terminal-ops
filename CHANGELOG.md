# Changelog

All notable changes to this project. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.0] - 2026-09-03

### Security model bump

The v1 threat model said *"act fast if your phone is lost."* v2 makes the
controls fail **closed by default** so a lost phone's access dies even if the
operator does nothing.

**Removed / changed (breaking):**

- **Passphrase now REQUIRED** on generated SSH keys. `termux-setup.sh` and
  `iphone-ish.sh` refuse to create an unencrypted key unless
  `--no-passphrase --i-understand-the-risk` is passed (both flags together).
- **SMTP is no longer the default email path.** `email-summary.sh` defaults to
  the local MTA and refuses third-party SMTP unless `EMAIL_SMTP_OK="yes"` is
  set explicitly.
- **Clipboard sync scoped down.** `connect.sh` only carries the clipboard with
  `--clipboard` (was default). `sync-clipboard.sh` prints a plaintext-on-server
  warning on every run and requires a one-time acknowledgment.
- **KILL_SESSIONS now defaults to `false`** in the auto-lock (it previously
  killed every Tailscale SSH session, including the admin's own).

**Added:**

- **Email redact-by-default**: Authorization/Bearer lines, private-key blocks
  (incl. single-line PEM), and 15+ token formats scrubbed before sending;
  `EMAIL_REDACT_EXTRA` for custom patterns.
- **Email encryption**: `EMAIL_ENCRYPT=gpg|age` attaches the full content
  encrypted; the body carries only a redacted preview. **Fails closed** — if
  encryption is requested but can't be produced, the email is refused.
- **Tailscale hardening script** (`setup/tailscale-hardening.sh`): 2FA
  checklist, **Tailnet Lock** (`tailscale lock init`), SSH-only ACL
  (phone→server:22). ACL identity is **auto-detected** and filled into
  `config/tailscale-acl.json`.
- **Dead-man's switch** (`setup/install-auto-lock.sh`,
  `scripts/auto-lock-server.sh`): heartbeat on every Tailscale SSH login via
  `~/.ssh/rc`; no heartbeat for `MAX_IDLE_HOURS` (default 24) revokes the
  phone key. Scheduler is a **system-level systemd timer** (survives reboot
  without a login session) or cron fallback. `--check-health` verifies the
  watchdog itself is alive.
- **Short-lived SSH certs** (`setup/install-ssh-ca.sh`,
  `scripts/sign-phone-key.sh`): phone key signed into a 48h certificate via
  `TrustedUserCAKeys`; lost-phone credential expires on its own. CA key is
  verified non-empty-passphrase. Old key removed by base64 blob (not comment).
- **Automated tests** (`tests/run-tests.sh`) + GitHub Actions CI, asserting
  fail-closed behavior.
- **README**: "Threat Model Tested" walkthrough table, bug-bounty scope
  disclaimer, "watchdog health" section, updated security model.

### Fixed (from adversarial review)

- Dead-man's switch: GNU-only `find -printf` broke revoke on macOS; the
  `grep -c || echo 0` bug produced `0\n0` and ran the wrong branch; future
  mtimes / missing / unreadable heartbeats now fail closed; cron install on a
  fresh system no longer silently fails.
- `TrustedUserCAKeys` detection now checks `sshd_config.d` drop-ins and
  verifies the active value via `sshd -T` (previously a duplicate directive
  could leave the CA untrusted while claiming success).
- CA key could be created with an empty passphrase — now detected and refused.
- Clipboard sync used single-quoted `~` remotely (silent no-op) — fixed.
- Queue fallback wrote world-readable files — now 0600/0700.
- `sign-phone-key.sh --dry-run` previously always failed — fixed.
- MIME boundary seeds used GNU-only `date +%s%N`; replaced with a portable
  `date +%s` + PID + `$RANDOM` tag for macOS/BSD compatibility.
- README "Audit status" note added: this is a solo-maintainer tool, not
  formally audited — test coverage ≠ an audit, stated explicitly.

## [1.0.0] - 2026-07-18

Initial release: Tailscale + SSH + tmux + opencode mobile workstation with
email summaries and clipboard sync.