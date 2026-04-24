#!/bin/bash
# remind-report-via-sendmessage.sh — PreToolUse hook on SendMessage.
#
# When foreman (team-lead) sends a substantive task brief to a smaller-model
# teammate (operator / mechanic / tester / paralegal / scout), inject a
# reminder that the closing instruction MUST be "Report back to foreman via
# SendMessage with: ...". Otherwise these models print findings to their own
# console and never transmit back, leaving foreman to re-do the work.
#
# WHY a hook, not a memory: memories decay — each session's foreman may or
# may not read the specific feedback. A hook is self-educating every turn,
# forever, without depending on memory discipline.
#
# Fires only when:
#   - tool is SendMessage
#   - recipient is in the small-model roster
#   - message is a substantive brief (≥200 chars) — short acks get a pass
#   - message does NOT already contain an explicit "SendMessage + foreman"
#     closing
#
# Pure reminder; never denies.
#
# Parameterisation:
#   HOOK_ENABLED_REMIND_REPORT_VIA_SENDMESSAGE — set to 0 to disable (default: 1)

set -euo pipefail

HOOK_ENABLED="${HOOK_ENABLED_REMIND_REPORT_VIA_SENDMESSAGE:-1}"
if [[ "$HOOK_ENABLED" != "1" ]]; then
  echo "{}"
  exit 0
fi

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "SendMessage" ]]; then
  echo "{}"
  exit 0
fi

to=$(jq -r '.tool_input.to // empty' <<<"$payload")

# Small-model teammates who benefit most from an explicit closing.
# Broadcast ("*") and larger models (engineer, foreman, team-lead) skip.
case "$to" in
  operator|mechanic|tester|paralegal|scout) : ;;
  *) echo "{}"; exit 0 ;;
esac

# Message body may be a string or a structured object (shutdown/plan-approval).
# Structured objects have no "brief" to report on — skip.
msg_type=$(jq -r '.tool_input.message | type' <<<"$payload" 2>/dev/null || echo "null")
if [[ "$msg_type" != "string" ]]; then
  echo "{}"
  exit 0
fi

message=$(jq -r '.tool_input.message // ""' <<<"$payload")

# Short acknowledgments / "Done" / "Ready" confirmations — no reminder needed.
# 200 chars is a deliberate threshold: task briefs are always substantially
# longer; "Ready." and "OK, will investigate" are always shorter.
msg_len=${#message}
if (( msg_len < 200 )); then
  echo "{}"
  exit 0
fi

# If the closing is already explicit, pass through. Look for any of:
#   - "SendMessage" (literal tool name)
#   - "send message" (natural-language form)
#   - "report back to foreman"
#   - "report to foreman"
#   - "reply to foreman"
# ... anywhere in the last 400 chars of the message (the "closing" window).
# bash's ${var: -N} returns empty when the string is shorter than N — so only
# take a suffix when we know the string is longer. (Don't use awk here: awk
# mishandles literal newlines in variables passed via -v.)
if (( msg_len > 400 )); then
  tail_window="${message: -400}"
else
  tail_window="$message"
fi

# Lowercase for match (closing phrases are case-insensitive in practice).
tail_lc=$(echo "$tail_window" | tr '[:upper:]' '[:lower:]')

if echo "$tail_lc" | grep -Eq 'sendmessage|send message|report back to foreman|report to foreman|reply to foreman'; then
  echo "{}"
  exit 0
fi

# Not found — inject reminder.
cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "REMINDER (remind-report-via-sendmessage.sh): this brief goes to a smaller-model teammate. End it with an explicit line like 'Report back to foreman via SendMessage with: <deliverable>'. Otherwise they print findings to their own console and you never see them — leaving you to redo the work."
  }
}
EOF
