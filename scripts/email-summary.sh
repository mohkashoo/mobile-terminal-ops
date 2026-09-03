#!/usr/bin/env bash
# Send a styled HTML email with opencode response content.
#
# Usage:
#   echo "opencode output..." | bash email-summary.sh \
#       --to you@example.com \
#       --subject "🔍 Opencode Response" \
#       --source "hunt:0.0"
#
# Email is sent via the configured transport:
#   local sendmail / mail  → default (data stays on your server's MTA)
#   curl SMTP              → OPT-IN ONLY, requires EMAIL_SMTP_OK="yes"
#
# The body is REDACTED by default (see EMAIL_REDACT). If EMAIL_ENCRYPT is
# set to "gpg" or "age", the full unredacted content is attached as an
# encrypted payload so the mail provider only ever sees ciphertext.
#
# Config: EMAIL_CONFIG env var, or config/email-config, or ~/.config/...

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

EMAIL_TO=""
EMAIL_SUBJECT="🔍 Opencode Response"
EMAIL_SOURCE="unknown"

# ── Parse args ───────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --to) EMAIL_TO="$2"; shift 2 ;;
        --subject) EMAIL_SUBJECT="$2"; shift 2 ;;
        --source) EMAIL_SOURCE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: echo 'output' | $0 --to email [--subject title] [--source pane]"
            exit 0 ;;
        *) shift ;;
    esac
done

# Read output from stdin
OUTPUT=$(cat)

if [ -z "$EMAIL_TO" ]; then
    echo "ERROR: --to is required" >&2
    exit 1
fi

# ── Load config ──────────────────────────────
CONFIG_PATH="${EMAIL_CONFIG:-}"
if [ -z "$CONFIG_PATH" ]; then
    if [ -f "$PROJECT_DIR/config/email-config" ]; then
        CONFIG_PATH="$PROJECT_DIR/config/email-config"
    elif [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/mobile-terminal-ops/email-config" ]; then
        CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/mobile-terminal-ops/email-config"
    fi
fi
if [ -n "$CONFIG_PATH" ] && [ -f "$CONFIG_PATH" ]; then
    . "$CONFIG_PATH"
fi

EMAIL_FROM="${EMAIL_FROM:-$EMAIL_TO}"
EMAIL_REDACT="${EMAIL_REDACT:-yes}"
EMAIL_ENCRYPT="${EMAIL_ENCRYPT:-none}"

# ── Redaction (default ON) ────────────────────
# Scrubs private-key blocks, Authorization/secret header lines, and common
# token formats (sk-, ghp_, xox, AWS keys, etc.) before anything is emailed.
redact() {
    [ "$EMAIL_REDACT" = "no" ] && { cat; return; }
    local data
    data=$(awk '
        BEGIN { redact=0 }
        /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/ {
            if ($0 ~ /-----END [A-Z0-9 ]*PRIVATE KEY-----/) { print "    [REDACTED - key material]"; next }
            redact=1; print "    [REDACTED - key material]"; next }
        redact && /-----END [A-Z0-9 ]*PRIVATE KEY-----/ { redact=0; print; next }
        redact { print "    [REDACTED - key material]"; next }
        { print }
    ' | sed -E \
        -e 's/([[:space:]]*Authorization[[:space:]]*[:=][[:space:]]*).*/\1[REDACTED]/Ig' \
        -e 's/([[:space:]]*Bearer[[:space:]]+)[A-Za-z0-9_.+=\/_-]+[[:space:]]*.*/\1[REDACTED]/Ig' \
        -e 's/(Api[-_ ]?Key|Access[-_ ]?Token|Refresh[-_ ]?Token|Client[-_ ]?Secret|Secret|Password|Passwd|Session[-_ ]?Token|Token|X-[A-Za-z-]*[Kk]ey)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_.+=\/_-]{6,}/\1: [REDACTED]/Ig' \
        -e 's/(sk-[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{16,}|sk_(live|test)_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|ghu_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|ghr_[A-Za-z0-9]{20,}|npm_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|ya29\.[0-9A-Za-z_-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})/[REDACTED]/g')
    if declare -p EMAIL_REDACT_EXTRA >/dev/null 2>&1 && declare -p EMAIL_REDACT_EXTRA 2>/dev/null | grep -q '^declare -a'; then
        for pat in "${EMAIL_REDACT_EXTRA[@]}"; do
            [ -n "$pat" ] && data=$(printf '%s\n' "$data" | sed -E "s|${pat}|[REDACTED]|g")
        done
    fi
    printf '%s\n' "$data"
}

REDACTED_OUTPUT=$(printf '%s\n' "$OUTPUT" | redact)

# ── Encryption (optional, strongly recommended with SMTP) ──
# Encrypts the FULL unredacted content so a third-party provider only
# transports ciphertext. The email body carries the redacted preview.
ENCRYPTED_FILE=""
if [ "$EMAIL_ENCRYPT" = "gpg" ] && command -v gpg >/dev/null 2>&1 && [ -n "${EMAIL_GPG_RECIPIENT:-}" ]; then
    ENCRYPTED_FILE=$(mktemp)
    if ! printf '%s\n' "$OUTPUT" | gpg --batch --yes --armor \
        --recipient "$EMAIL_GPG_RECIPIENT" --output "$ENCRYPTED_FILE" --encrypt 2>/dev/null; then
        echo "ERROR: gpg encryption failed (is $EMAIL_GPG_RECIPIENT in your keyring?)" >&2
        rm -f "$ENCRYPTED_FILE"; ENCRYPTED_FILE=""
    else
        ATTACH_NAME="summary.gpg.asc"
    fi
elif [ "$EMAIL_ENCRYPT" = "age" ] && command -v age >/dev/null 2>&1 && [ -n "${EMAIL_AGE_PUBKEY:-}" ]; then
    ENCRYPTED_FILE=$(mktemp)
    if ! printf '%s\n' "$OUTPUT" | age --recipient "$EMAIL_AGE_PUBKEY" --output "$ENCRYPTED_FILE" 2>/dev/null; then
        echo "ERROR: age encryption failed (is $EMAIL_AGE_PUBKEY a valid recipient?)" >&2
        rm -f "$ENCRYPTED_FILE"; ENCRYPTED_FILE=""
    else
        ATTACH_NAME="summary.age"
    fi
fi

# Fail CLOSED: if the user asked for encryption and we couldn't produce a
# payload, do NOT send plaintext through a mail path.
if [ "$EMAIL_ENCRYPT" != "none" ] && [ -z "$ENCRYPTED_FILE" ]; then
    echo "ERROR: EMAIL_ENCRYPT=$EMAIL_ENCRYPT but no encrypted payload was produced." >&2
    echo "Refusing to send. Check gpg/age are installed and the recipient is set," >&2
    echo "or set EMAIL_ENCRYPT=\"none\" in config/email-config to explicitly allow plaintext." >&2
    exit 1
fi

# ── Escape HTML ──────────────────────────────
escape_html() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

ESCAPED_OUTPUT=$(printf '%s\n' "$REDACTED_OUTPUT" | escape_html)
ESCAPED_SUBJECT=$(echo "$EMAIL_SUBJECT" | escape_html)
ESCAPED_SOURCE=$(echo "$EMAIL_SOURCE" | escape_html)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')

if [ -n "$ENCRYPTED_FILE" ]; then
    ENCRYPT_NOTICE="
      <tr><td style='color:#00d4aa;font-size:12px;padding:8px 20px;'>
        🔐 Full summary encrypted ($ATTACH_NAME). Decrypt on your phone:
        ${EMAIL_ENCRYPT} -d $ATTACH_NAME. Redacted preview below.
      </td></tr>"
else
    ENCRYPT_NOTICE=""
fi

# ── Build HTML body (redacted preview) ───────
read -r -d '' HTML_BODY <<EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;background-color:#0f0f1a;font-family:'Courier New',monospace;">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">
    <tr>
      <td style="padding:30px 20px;">
        <!-- Header -->
        <table width="100%" cellpadding="0" cellspacing="0" style="border-bottom:2px solid #00d4aa;padding-bottom:15px;">
          <tr>
            <td>
              <h1 style="color:#00d4aa;font-size:20px;margin:0;font-weight:600;">$ESCAPED_SUBJECT</h1>
              <p style="color:#666;font-size:12px;margin:5px 0 0 0;">
                $TIMESTAMP &middot; $ESCAPED_SOURCE
              </p>
            </td>
          </tr>
        </table>
        $ENCRYPT_NOTICE
        <!-- Content -->
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-top:20px;background:#1a1a2e;border-radius:8px;">
          <tr>
            <td style="padding:20px;font-size:13px;line-height:1.5;color:#e0e0e0;white-space:pre-wrap;word-break:break-word;font-family:'Courier New',monospace;">
$ESCAPED_OUTPUT
            </td>
          </tr>
        </table>
        <!-- Footer -->
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-top:20px;">
          <tr>
            <td style="color:#444;font-size:11px;text-align:center;">
              Mobile Terminal Ops &middot; automated email summary &middot; body redacted by default
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
EOF

# ── Build MIME message ───────────────────────
build_mime() {
    if [ -z "$ENCRYPTED_FILE" ]; then
        # Simple multipart/alternative (plain + redacted html)
        local boundary="----=_NextPart_$(date +%s)-$$-${RANDOM:-0}"
        cat <<EOFMAIL
From: ${EMAIL_FROM}
To: ${EMAIL_TO}
Subject: ${EMAIL_SUBJECT}
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="${boundary}"

--${boundary}
Content-Type: text/plain; charset="utf-8"

${REDACTED_OUTPUT}

--${boundary}
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: 8bit

${HTML_BODY}

--${boundary}--
EOFMAIL
    else
        # multipart/mixed: redacted preview + encrypted attachment
        local mixed="----=_Mixed_$(date +%s)-$$-${RANDOM:-0}"
        local alt="----=_Alt_$(date +%s)-$$-${RANDOM:-0}"
        local enc_b64
        enc_b64=$(base64 < "$ENCRYPTED_FILE" | tr -d '\r')
        cat <<EOFMAIL
From: ${EMAIL_FROM}
To: ${EMAIL_TO}
Subject: ${EMAIL_SUBJECT}
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="${mixed}"

--${mixed}
Content-Type: multipart/alternative; boundary="${alt}"

--${alt}
Content-Type: text/plain; charset="utf-8"

Encrypted summary. Decrypt ${ATTACH_NAME} with ${EMAIL_ENCRYPT}:

Redacted preview:
${REDACTED_OUTPUT}

--${alt}
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: 8bit

${HTML_BODY}

--${alt}--
--${mixed}
Content-Type: application/octet-stream; name="${ATTACH_NAME}"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="${ATTACH_NAME}"

${enc_b64}

--${mixed}--
EOFMAIL
    fi
}

MSG_FILE=$(mktemp)
build_mime > "$MSG_FILE"
trap 'rm -f "$MSG_FILE" ${ENCRYPTED_FILE:+$ENCRYPTED_FILE}' EXIT

# ── Send ─────────────────────────────────────
send_via_curl_smtp() {
    curl -s --ssl-reqd \
        --mail-from "$EMAIL_FROM" \
        --mail-rcpt "$EMAIL_TO" \
        --user "${SMTP_USER}:${SMTP_PASS}" \
        --upload-file "$MSG_FILE" \
        "${SMTP_URL}" 2>/dev/null
}

send_via_sendmail() {
    /usr/sbin/sendmail -t < "$MSG_FILE" 2>/dev/null
}

send_via_mail() {
    echo "$HTML_BODY" | mail -s "$EMAIL_SUBJECT" -a "Content-Type: text/html" "$EMAIL_TO" 2>/dev/null
}

SMTP_CONFIGURED=false
if [ -n "${SMTP_URL:-}" ] && [ -n "${SMTP_USER:-}" ] && [ -n "${SMTP_PASS:-}" ]; then
    SMTP_CONFIGURED=true
fi

# Try: local sendmail > mail > (opt-in) curl SMTP > log fallback
# Local relay is the DEFAULT and is always tried first so data never has to
# leave your own infrastructure unless you explicitly opt in.
if command -v /usr/sbin/sendmail >/dev/null 2>&1; then
    if send_via_sendmail; then
        echo "email sent via local sendmail to $EMAIL_TO"
        exit 0
    fi
    echo "sendmail failed, trying mail command..." >&2
fi

if command -v mail >/dev/null 2>&1 && [ -z "$ENCRYPTED_FILE" ]; then
    # The mail transport only carries the HTML body; it DROPS the encrypted
    # attachment, so it is only used when there is nothing to drop.
    if send_via_mail; then
        echo "email sent via local mail command to $EMAIL_TO"
        exit 0
    fi
    echo "mail command failed..." >&2
fi

if [ "$SMTP_CONFIGURED" = true ]; then
    if [ "${EMAIL_SMTP_OK:-}" != "yes" ]; then
        echo "NOTE: SMTP_* are set but EMAIL_SMTP_OK != 'yes'." >&2
        echo "Refusing to send opencode output through a third-party mail provider." >&2
        echo "Set EMAIL_SMTP_OK=\"yes\" in config/email-config to explicitly allow it." >&2
    else
        echo "WARNING: sending through third-party SMTP (${SMTP_URL})." >&2
        echo "         Prefer EMAIL_ENCRYPT=\"gpg|age\" so the provider can't read it." >&2
        if send_via_curl_smtp; then
            echo "email sent via opt-in curl SMTP to $EMAIL_TO"
            exit 0
        fi
        echo "curl SMTP failed..." >&2
    fi
fi

# Last resort: write to file (hardened: private queue dir + file perms)
local_queue="$PROJECT_DIR/email-queue"
mkdir -p "$local_queue"
chmod 700 "$local_queue" 2>/dev/null || true
local_file="${local_queue}/$(date +%Y%m%d-%H%M%S)-${EMAIL_TO}.eml"
cp "$MSG_FILE" "$local_file"
chmod 600 "$local_file" 2>/dev/null || true
echo "email queued to $local_file (no MTA available)" >&2
exit 1