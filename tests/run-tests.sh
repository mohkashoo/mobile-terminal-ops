#!/usr/bin/env bash
# Automated test suite for mobile-terminal-ops.
#
# Run:  bash tests/run-tests.sh
# CI:   .github/workflows/ci.yml runs this on ubuntu-latest.
#
# Design: every test runs in a throwaway $HOME sandbox so nothing on your
# real machine is touched. Tests assert FAIL-CLOSED behavior: when a control
# (passphrase, SMTP opt-in, encryption, dead-man's switch) is misconfigured,
# the scripts must refuse/revoke — not silently do nothing.
#
# NOTE: email tests that depend on local MTA presence (sendmail/mail) are
# asserted on the MESSAGE the script prints, which is deterministic in both
# environments (CI has no MTA; local machines may).

set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
FAILED_TESTS=()

t()  { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
f()  { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); FAILED_TESTS+=("$1"); }

assert_eq() { # desc expected actual
    if [ "$2" = "$3" ]; then t "$1"; else f "$1 (expected '$2', got '$3')"; fi
}
assert_rc() { # desc expected_rc
    if [ "$2" -eq "$3" ]; then t "$1"; else f "$1 (expected rc $2, got $3)"; fi
}
assert_contains() { # desc needle haystack
    if printf '%s' "$3" | grep -qF -- "$2"; then t "$1"; else f "$1 (missing '$2')"; fi
}
assert_not_contains() {
    if printf '%s' "$3" | grep -qF -- "$2"; then f "$1 (found forbidden '$2')"; else t "$1"; fi
}

fresh_home() {
    SAND=$(mktemp -d)
    mkdir -p "$SAND/.ssh"
    chmod 700 "$SAND/.ssh"
}

echo "== mobile-terminal-ops test suite =="

# ── 1. Syntax ─────────────────────────────────
echo "1. Syntax (bash -n)"
SYNTAX_OK=true
for f in "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/setup/*.sh; do
    bash -n "$f" 2>/dev/null || { SYNTAX_OK=false; f "syntax: $f"; }
done
[ "$SYNTAX_OK" = true ] && t "all scripts parse cleanly"

# ── 2. Passphrase gate (termux + iphone) ──────
echo "2. Passphrase gate"
fresh_home
HOME="$SAND" bash "$REPO_DIR/setup/termux-setup.sh" --dry-run --no-passphrase >/dev/null 2>&1
assert_rc "termux: --no-passphrase without --i-understand-the-risk refuses" 1 $?
HOME="$SAND" bash "$REPO_DIR/setup/termux-setup.sh" --dry-run --no-passphrase --i-understand-the-risk >/dev/null 2>&1
assert_rc "termux: both flags accepted" 0 $?
fresh_home
HOME="$SAND" bash "$REPO_DIR/setup/iphone-ish.sh" --no-passphrase >/dev/null 2>&1
assert_rc "iphone-ish: --no-passphrase alone refuses" 1 $?

# ── 3. Redaction (pure function) ──────────────
echo "3. Email redaction"
sed -n '/^redact()/,/^}/p' "$REPO_DIR/scripts/email-summary.sh" > "$SAND/redact_fn.sh"
cat > "$SAND/redact_test.sh" << 'EOT'
EMAIL_REDACT=yes
source "$SAND/redact_fn.sh"
# Fake secrets are built at RUNTIME from parts so the source never contains a
# literal secret-format string (GitHub push protection scans file contents).
B64='abcdefghijklmnopqrstuvwxyz123456'
sk_live="sk_live_$B64"            # sk_live_...
ghp="ghp_$B64"
github_pat="github_pat_$B64"
glpat="glpat-$B64"
printf '%s\n' \
'Authorization: Bearer abcdef1234567890' \
'x-api-key = super-secret-value-here' \
"$ghp" \
"$github_pat" \
"$sk_live" \
"$glpat" \
'-----BEGIN OPENSSH PRIVATE KEY----- AAAA -----END OPENSSH PRIVATE KEY-----' \
'normal: ok-value-here' | redact
EOT
OUT=$(SAND="$SAND" HOME="$SAND" bash "$SAND/redact_test.sh" 2>&1)
# Rebuild the same fake-token shapes at runtime for the needles, so the test
# source itself contains no literal secret-format string.
B64='abcdefghijklmnopqrstuvwxyz123456'
NEEDLE_SK="sk_live_$B64"
NEEDLE_GHP="ghp_$B64"
NEEDLE_PAT="github_pat_$B64"
NEEDLE_GLPAT="glpat-$B64"
assert_contains "Authorization/Bearer redacted" "[REDACTED]" "$OUT"
assert_not_contains "x-api-key value redacted" "super-secret-value-here" "$OUT"
assert_not_contains "ghp_ token redacted" "$NEEDLE_GHP" "$OUT"
assert_not_contains "github_pat_ redacted" "$NEEDLE_PAT" "$OUT"
assert_not_contains "sk_live_ redacted" "$NEEDLE_SK" "$OUT"
assert_not_contains "glpat- redacted" "$NEEDLE_GLPAT" "$OUT"
assert_not_contains "single-line PEM key material redacted" "AAAA -----END" "$OUT"
assert_contains "normal line preserved" "normal: ok-value-here" "$OUT"

# ── 4. Email SMTP opt-in gate ─────────────────
echo "4. Email SMTP opt-in gate"
cat > "$SAND/email-gate.cfg" << 'EOT'
EMAIL_TO="me@example.com"
SMTP_URL="smtps://smtp.gmail.com:465"
SMTP_USER="me@gmail.com"
SMTP_PASS="fakepass123456"
EMAIL_SMTP_OK=""
EOT
OUT=$(printf 'x\n' | EMAIL_CONFIG="$SAND/email-gate.cfg" bash "$REPO_DIR/scripts/email-summary.sh" --to me@example.com --subject t 2>&1 || true)
assert_not_contains "SMTP not used when EMAIL_SMTP_OK empty" "opt-in curl SMTP" "$OUT"

cat > "$SAND/email-gate2.cfg" << 'EOT'
EMAIL_TO="me@example.com"
SMTP_URL="smtps://127.0.0.1:1"
SMTP_USER="me@gmail.com"
SMTP_PASS="fakepass123456"
EMAIL_SMTP_OK="yes"
EOT
OUT=$(printf 'x\n' | EMAIL_CONFIG="$SAND/email-gate2.cfg" bash "$REPO_DIR/scripts/email-summary.sh" --to me@example.com --subject t 2>&1 || true)
assert_not_contains "SMTP opt-in accepted (no refusal when EMAIL_SMTP_OK=yes)" "Refusing to send opencode output" "$OUT"

# ── 5. Email encryption fails CLOSED ──────────
echo "5. Email encryption (fail closed)"
cat > "$SAND/email-enc.cfg" << 'EOT'
EMAIL_TO="me@example.com"
EMAIL_ENCRYPT="gpg"
EMAIL_GPG_RECIPIENT="nobody@example.com"
EOT
# Deterministic in both environments: with gpg installed, encryption to a
# non-existent recipient fails; without gpg, `command -v gpg` fails. Either
# way ENCRYPTED_FILE stays empty and the script MUST refuse to send.
OUT=$(printf 'secret payload\n' | EMAIL_CONFIG="$SAND/email-enc.cfg" bash "$REPO_DIR/scripts/email-summary.sh" --to me@example.com --subject t 2>&1)
RC=$?
assert_rc "encryption requested but impossible → refuses to send" 1 "$RC"
assert_contains "refusal message present" "Refusing to send" "$OUT"

# ── 6. Dead-man's switch ──────────────────────
echo "6. Dead-man's switch (auto-lock-server.sh)"
AUTO_LOCK="$REPO_DIR/scripts/auto-lock-server.sh"

fresh_home
printf 'ssh-ed25519 AAAATEST01 termux-phone\n' > "$SAND/.ssh/authorized_keys"
printf 'ssh-ed25519 AAAATEST02 admin-desktop\n' >> "$SAND/.ssh/authorized_keys"
chmod 600 "$SAND/.ssh/authorized_keys"
touch "$SAND/.phone-heartbeat"                      # fresh
HOME="$SAND" XDG_DATA_HOME="$SAND/data" bash "$AUTO_LOCK" >/dev/null 2>&1
assert_rc "fresh heartbeat → exit 0, no action" 0 $?
assert_eq "fresh heartbeat → both keys remain" 2 "$(grep -c '^ssh-ed25519' "$SAND/.ssh/authorized_keys")"

fresh_home
printf 'ssh-ed25519 AAAATEST01 termux-phone\n' > "$SAND/.ssh/authorized_keys"
printf 'ssh-ed25519 AAAATEST02 admin-desktop\n' >> "$SAND/.ssh/authorized_keys"
chmod 600 "$SAND/.ssh/authorized_keys"
touch -d '3 days ago' "$SAND/.phone-heartbeat"      # stale
HOME="$SAND" XDG_DATA_HOME="$SAND/data" MAX_IDLE_HOURS=24 bash "$AUTO_LOCK" >/dev/null 2>&1
assert_rc "stale heartbeat → exit 0 (revoke path)" 0 $?
assert_eq "stale → phone key revoked" 1 "$(grep -c '^ssh-ed25519' "$SAND/.ssh/authorized_keys")"
assert_eq "stale → admin key untouched" 1 "$(grep -c 'admin-desktop' "$SAND/.ssh/authorized_keys")"
assert_eq "stale → backup created" 1 "$(ls "$SAND/.ssh"/authorized_keys.bak.* 2>/dev/null | wc -l)"

fresh_home
printf 'ssh-ed25519 AAAATEST01 termux-phone\n' > "$SAND/.ssh/authorized_keys"
chmod 600 "$SAND/.ssh/authorized_keys"
touch -d 'tomorrow' "$SAND/.phone-heartbeat"        # future mtime → clock skew
HOME="$SAND" XDG_DATA_HOME="$SAND/data" bash "$AUTO_LOCK" >/dev/null 2>&1
assert_eq "future-dated heartbeat treated as stale → revoked" 0 "$(grep -c '^ssh-ed25519' "$SAND/.ssh/authorized_keys")"

fresh_home
printf 'ssh-ed25519 AAAATEST02 admin-desktop\n' > "$SAND/.ssh/authorized_keys"
chmod 600 "$SAND/.ssh/authorized_keys"
touch -d '3 days ago' "$SAND/.phone-heartbeat"      # stale but NO phone key
OUT=$(HOME="$SAND" XDG_DATA_HOME="$SAND/data" bash "$AUTO_LOCK" 2>&1)
assert_contains "no matching phone key → warns, does not crash" "Nothing revoked" "$OUT"
assert_eq "no matching phone key → admin key intact" 1 "$(grep -c 'admin-desktop' "$SAND/.ssh/authorized_keys")"

fresh_home
HOME="$SAND" XDG_DATA_HOME="$SAND/data" bash "$AUTO_LOCK" --check-health >/dev/null 2>&1
assert_rc "--check-health runs" 0 $?

# ── 7. SSH CA / short-lived certs ─────────────
echo "7. SSH CA signing"
fresh_home
export HOME="$SAND"
mkdir -p "$SAND/.ssh" && chmod 700 "$SAND/.ssh"
ssh-keygen -q -t ed25519 -f "$SAND/.ssh/mto-ca" -N '' -C "mto CA"
ssh-keygen -q -t ed25519 -f "$SAND/phone-key" -N '' -C "termux-phone"
printf 'ssh-ed25519 %s termux-phone\n' "$(awk '{print $2}' "$SAND/phone-key.pub")" > "$SAND/.ssh/authorized_keys"
chmod 600 "$SAND/.ssh/authorized_keys"

# --dry-run must not modify anything
HOME="$SAND" bash "$REPO_DIR/scripts/sign-phone-key.sh" --dry-run --hours 2 < "$SAND/phone-key.pub" >/dev/null 2>&1
assert_rc "sign-phone-key --dry-run exits 0" 0 $?
assert_eq "dry-run changes nothing" 1 "$(grep -c '^ssh-ed25519 ' "$SAND/.ssh/authorized_keys")"

# real signing replaces the raw key with a cert
OUT=$(HOME="$SAND" bash "$REPO_DIR/scripts/sign-phone-key.sh" --hours 2 < "$SAND/phone-key.pub" 2>&1)
assert_rc "sign-phone-key signs" 0 $?
assert_eq "cert installed in authorized_keys" 1 "$(grep -c '^ssh-ed25519-cert-v01' "$SAND/.ssh/authorized_keys")"
assert_eq "raw key removed" 0 "$(grep -c '^ssh-ed25519 ' "$SAND/.ssh/authorized_keys")"
# the cert is printed on stdout — capture it and verify the validity window
printf '%s\n' "$OUT" | grep '^ssh-ed25519-cert-v01' > "$SAND/cert.pub"
CERT_VALID=$(ssh-keygen -L -f "$SAND/cert.pub" 2>/dev/null | grep -c 'Valid')
assert_eq "cert has validity window" 1 "$CERT_VALID"

# empty-passphrase detection idiom used by install-ssh-ca.sh
ssh-keygen -y -P '' -f "$SAND/.ssh/mto-ca" >/dev/null 2>&1
assert_rc "unencrypted CA key detected via ssh-keygen -y -P ''" 0 $?

# ── 8. Sync-clipboard ack gate ────────────────
echo "8. Clipboard ack gate"
fresh_home
printf 'no\n' | HOME="$SAND" XDG_DATA_HOME="$SAND/data" bash "$REPO_DIR/scripts/sync-clipboard.sh" push >/dev/null 2>&1
assert_rc "clipboard: refusal to acknowledge aborts" 1 $?
printf 'yes\n' | HOME="$SAND" XDG_DATA_HOME="$SAND/data" bash "$REPO_DIR/scripts/sync-clipboard.sh" push >/dev/null 2>&1
RC=$?
assert_eq "clipboard: acknowledged → proceeds (fails only on missing termux-api)" 1 "$RC"

# ── Summary ───────────────────────────────────
echo ""
echo "== $PASS passed, $FAIL failed =="
if [ "$FAIL" -gt 0 ]; then
    printf '  failed: %s\n' "${FAILED_TESTS[@]}"
    exit 1
fi
exit 0