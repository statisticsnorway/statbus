#!/bin/bash
# remind-plan-update.sh — PreToolUse hook on TaskUpdate.
#
# When a task is marked completed, inject a short additionalContext reminder
# to update the current plan if the task corresponds to an open plan item.
#
# Fires only on `status: "completed"` — other updates pass through.
# Pure reminder; never denies.

set -euo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "TaskUpdate" ]]; then
  echo "{}"
  exit 0
fi

status=$(jq -r '.tool_input.status // empty' <<<"$payload")

if [[ "$status" != "completed" ]]; then
  echo "{}"
  exit 0
fi

task_id=$(jq -r '.tool_input.taskId // "?"' <<<"$payload")

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "REMINDER (remind-plan-update.sh): task #${task_id} marked completed — if it corresponds to an open item in the current plan, update the plan to reflect completion."
  }
}
EOF
