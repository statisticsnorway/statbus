#!/bin/bash
# remind-backlog-after-commit.sh — PostToolUse hook on Bash.
#
# After a `git commit` lands, inject a reminder to update the relevant
# Backlog.md ticket (mcp__backlog__task_edit) so the board never trails the
# tree. The King's standing rule: every ruling, verdict, and unit of progress
# lands on its ticket same-turn — the board is the shared source of truth
# across sessions, and a commit without its ticket update is invisible
# progress.
#
# WHY a hook, not a memory: memories decay — each session may or may not
# recall the discipline. A hook is self-educating on every commit, forever.
#
# Fires only when:
#   - tool is Bash
#   - the command contains a `git commit` invocation (covers `git -C ... commit`
#     and compound `git add ... && git commit ...` forms)
#   - the command does NOT itself stage .backlog/ paths (a board-sync commit IS
#     the backlog update — reminding there is pure noise)
#
# Pure reminder; never denies.
#
# Parameterisation:
#   HOOK_ENABLED_REMIND_BACKLOG_AFTER_COMMIT — set to 0 to disable (default: 1)

set -euo pipefail

HOOK_ENABLED="${HOOK_ENABLED_REMIND_BACKLOG_AFTER_COMMIT:-1}"
if [[ "$HOOK_ENABLED" != "1" ]]; then
  echo "{}"
  exit 0
fi

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "Bash" ]]; then
  echo "{}"
  exit 0
fi

command=$(jq -r '.tool_input.command // ""' <<<"$payload")

# Match a real `git commit` invocation: `git` then `commit` on the same
# command with only flags/paths between (covers `git -C <dir> commit`).
# Deliberately NOT matching the mere substring "commit" (rebase messages,
# echo text, etc. would false-fire).
if ! echo "$command" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)'; then
  echo "{}"
  exit 0
fi

# A commit that stages .backlog/ paths is itself the board update — skip.
if echo "$command" | grep -q '\.backlog'; then
  echo "{}"
  exit 0
fi

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "REMINDER (remind-backlog-after-commit.sh): a git commit just landed. If it represents progress on a Backlog.md ticket, update that ticket NOW (mcp__backlog__task_edit — comment with the commit SHA, check criteria, adjust status) and commit the .backlog change. If the board is already current for this commit, proceed."
  }
}
EOF
