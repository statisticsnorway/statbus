#!/bin/bash
# remind-hug-after-commit.sh — PostToolUse hook on Bash.
#
# After a `git commit` lands, inject a reminder to update the relevant
# hug task (hug task note / check / done) so the board never trails the
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
#   - the command does NOT run in the task worktree .hug/tasks (a board commit IS
#     the task update — reminding there is pure noise)
#
# Pure reminder; never denies.
#
# Parameterisation:
#   HOOK_ENABLED_REMIND_HUG_AFTER_COMMIT — set to 0 to disable (default: 1)

set -euo pipefail

HOOK_ENABLED="${HOOK_ENABLED_REMIND_HUG_AFTER_COMMIT:-1}"
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

# A commit in the task worktree is itself the board update — skip.
if echo "$command" | grep -q '\.hug/tasks'; then
  echo "{}"
  exit 0
fi

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "REMINDER (remind-hug-after-commit.sh): a git commit just landed. If it represents progress on a hug task, update that task NOW (hug task note ID with the commit SHA, hug task check ID N for verified checks, hug task done ID when all are ticked), then hug task sync. If the board is already current for this commit, proceed."
  }
}
EOF
