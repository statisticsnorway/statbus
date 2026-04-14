#!/usr/bin/env bash
#
# UPGRADE_CALLBACK script. Posts a Slack message after every upgrade
# attempt — branches between success and rollback-failure renderings
# based on $STATBUS_ROLLBACK_FAILED.
#
# Usage in .env:
#   UPGRADE_CALLBACK=./ops/notify-slack.sh
#
# Required environment (set by the upgrade service):
#   STATBUS_VERSION       — version targeted by this upgrade attempt
#   STATBUS_FROM_VERSION  — version the server was on going in
#   STATBUS_SERVER        — hostname of the server
#   STATBUS_URL           — public URL of the instance
#
# Failure-only environment (set when rollback could NOT restore git):
#   STATBUS_ROLLBACK_FAILED  — "1" when present; absent on success path
#   STATBUS_ROLLBACK_ERROR   — short reason string from the failed git restore
#   STATBUS_RECOVERY_CMD     — exact command the operator should run
#
# Required in .env (or process environment):
#   SLACK_TOKEN          — Slack Bot User OAuth Token (xoxb-...)
set -euo pipefail

CHANNEL="#statbus-utvikling"

if [ -z "${SLACK_TOKEN:-}" ]; then
    echo "notify-slack: SLACK_TOKEN not set, skipping notification" >&2
    exit 0
fi

if [ "${STATBUS_ROLLBACK_FAILED:-}" = "1" ]; then
    # Rollback-failure alert: distinctive (siren prefix), names the
    # exact recovery command so the on-call operator can act without
    # opening any docs. The recovery command goes in a code block so
    # Slack renders it copy-pasteable.
    HEADER=":rotating_light: ROLLBACK FAILED on *${STATBUS_SERVER:-unknown}*"
    BODY="Target version: \`${STATBUS_VERSION:-unknown}\` (from \`${STATBUS_FROM_VERSION:-unknown}\`)"
    BODY="${BODY}\nReason: ${STATBUS_ROLLBACK_ERROR:-unknown}"
    BODY="${BODY}\nServices are STOPPED. Maintenance mode is ON. Recovery:"
    if [ -n "${STATBUS_RECOVERY_CMD:-}" ]; then
        BODY="${BODY}\n\`\`\`${STATBUS_RECOVERY_CMD}\`\`\`"
    fi
    if [ -n "${STATBUS_URL:-}" ]; then
        BODY="${BODY}\nInstance: <${STATBUS_URL}>"
    fi
    TEXT="${HEADER}\n${BODY}"
else
    # Success path.
    TEXT="Upgraded *${STATBUS_SERVER:-unknown}* from \`${STATBUS_FROM_VERSION:-unknown}\` to \`${STATBUS_VERSION:-unknown}\`"
    if [ -n "${STATBUS_URL:-}" ]; then
        TEXT="${TEXT} — <${STATBUS_URL}>"
    fi
fi

# jq isn't always installed; build the payload by hand. Slack tolerates
# literal \n in JSON string values for line breaks.
PAYLOAD=$(printf '{"channel":"%s","text":"%s","unfurl_links":false}' \
    "${CHANNEL}" "${TEXT}")

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
