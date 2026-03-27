#!/usr/bin/env bash
#
# Sample UPGRADE_CALLBACK script that posts to Slack after a successful upgrade.
#
# Usage in .env:
#   UPGRADE_CALLBACK=./devops/notify-slack.sh
#
# Required environment (set by the upgrade daemon):
#   STATBUS_VERSION      — the new version (e.g., v2026.03.1)
#   STATBUS_FROM_VERSION — the previous version
#   STATBUS_SERVER       — hostname of the server
#   STATBUS_URL          — public URL of the instance
#
# Required in .env (or process environment):
#   SLACK_TOKEN          — Slack Bot User OAuth Token (xoxb-...)
#
set -euo pipefail

CHANNEL="#statbus-utvikling"

if [ -z "${SLACK_TOKEN:-}" ]; then
    echo "notify-slack: SLACK_TOKEN not set, skipping notification" >&2
    exit 0
fi

TEXT="Upgraded *${STATBUS_SERVER:-unknown}* from \`${STATBUS_FROM_VERSION:-unknown}\` to \`${STATBUS_VERSION:-unknown}\`"
if [ -n "${STATBUS_URL:-}" ]; then
    TEXT="${TEXT} — <${STATBUS_URL}>"
fi

PAYLOAD=$(cat <<EOF
{
  "channel": "${CHANNEL}",
  "text": "${TEXT}",
  "unfurl_links": false
}
EOF
)

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}")

if [ "${HTTP_CODE}" -ge 200 ] && [ "${HTTP_CODE}" -lt 300 ]; then
    echo "notify-slack: posted to ${CHANNEL}"
else
    echo "notify-slack: Slack API returned HTTP ${HTTP_CODE}" >&2
    exit 1
fi
