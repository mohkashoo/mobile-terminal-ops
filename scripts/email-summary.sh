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
#   curl SMTP  → requires SMTP_* settings in config
#   sendmail   → fallback if available
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

# ── Escape HTML ──────────────────────────────
escape_html() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

ESCAPED_OUTPUT=$(echo "$OUTPUT" | escape_html)
ESCAPED_SUBJECT=$(echo "$EMAIL_SUBJECT" | escape_html)
ESCAPED_SOURCE=$(echo "$EMAIL_SOURCE" | escape_html)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')

# ── Build HTML body ──────────────────────────
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
              Mobile Terminal Ops &middot; automated email summary
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
EOF

# ── Send ─────────────────────────────────────
send_via_curl_smtp() {
    local boundary="----=_NextPart_$(date +%s%N)"
    local email_file
    email_file=$(mktemp)

    cat > "$email_file" <<EOFMAIL
From: ${EMAIL_FROM}
To: ${EMAIL_TO}
Subject: ${EMAIL_SUBJECT}
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="${boundary}"

--${boundary}
Content-Type: text/plain; charset="utf-8"

${OUTPUT}

--${boundary}
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: 8bit

${HTML_BODY}

--${boundary}--
EOFMAIL

    curl -s --ssl-reqd \
        --mail-from "$EMAIL_FROM" \
        --mail-rcpt "$EMAIL_TO" \
        --user "${SMTP_USER}:${SMTP_PASS}" \
        --upload-file "$email_file" \
        "${SMTP_URL}" 2>/dev/null
    local rc=$?
    rm -f "$email_file"
    return $rc
}

send_via_sendmail() {
    local boundary="----=_NextPart_$(date +%s%N)"
    (
        echo "From: ${EMAIL_FROM}"
        echo "To: ${EMAIL_TO}"
        echo "Subject: ${EMAIL_SUBJECT}"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/alternative; boundary=\"${boundary}\""
        echo ""
        echo "--${boundary}"
        echo "Content-Type: text/plain; charset=\"utf-8\""
        echo ""
        echo "${OUTPUT}"
        echo ""
        echo "--${boundary}"
        echo "Content-Type: text/html; charset=\"utf-8\""
        echo "Content-Transfer-Encoding: 8bit"
        echo ""
        echo "${HTML_BODY}"
        echo ""
        echo "--${boundary}--"
    ) | /usr/sbin/sendmail -t 2>/dev/null
}

send_via_mail() {
    echo "$HTML_BODY" | mail -s "$EMAIL_SUBJECT" -a "Content-Type: text/html" "$EMAIL_TO" 2>/dev/null
}

# Try: curl SMTP > sendmail > mail > log fallback
if [ -n "${SMTP_URL:-}" ] && [ -n "${SMTP_USER:-}" ] && [ -n "${SMTP_PASS:-}" ]; then
    if send_via_curl_smtp; then
        echo "email sent via curl SMTP to $EMAIL_TO"
        exit 0
    fi
    echo "curl SMTP failed, trying sendmail..." >&2
fi

if command -v /usr/sbin/sendmail &>/dev/null; then
    if send_via_sendmail; then
        echo "email sent via sendmail to $EMAIL_TO"
        exit 0
    fi
    echo "sendmail failed, trying mail command..." >&2
fi

if command -v mail &>/dev/null; then
    if send_via_mail; then
        echo "email sent via mail to $EMAIL_TO"
        exit 0
    fi
fi

# Last resort: write to file
local_queue="$PROJECT_DIR/email-queue"
mkdir -p "$local_queue"
local_file="${local_queue}/$(date +%Y%m%d-%H%M%S)-${EMAIL_TO}.eml"
cat > "$local_file" <<EOF
From: ${EMAIL_FROM}
To: ${EMAIL_TO}
Subject: ${EMAIL_SUBJECT}
Content-Type: text/html; charset="utf-8"

${HTML_BODY}
EOF
echo "email queued to $local_file (no MTA available)" >&2
exit 1
