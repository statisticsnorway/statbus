#!/bin/bash
# require-hug-tasks.sh — PreToolUse hook on the harness TaskCreate tool.
#
# Blocks the built-in TaskCreate. This project's canonical task store is
# hug (the hug task CLI and the hug MCP task_* tools), not the harness Task* list.
#
# WHY (in the deny message, not in always-on docs): the harness Task* list is
# volatile here — it does not survive /clear or compaction and is not the shared
# source of truth. hug is. Creating tasks in the harness list fragments
# the board. The generic "consider using TaskCreate" system reminder is
# project-agnostic and does not know this; this hook is the correction,
# delivered only when TaskCreate is actually attempted.

set -euo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

# Only guard the harness TaskCreate; the hug MCP tool (mcp__hug__task_new)
# has a different name and passes straight through.
if [[ "$tool" != "TaskCreate" ]]; then
  echo "{}"
  exit 0
fi

reason_text="BLOCKED: the harness TaskCreate tool is disabled in this repo. Tasks live in hug, not the harness Task* list.

WHY: the harness Task* list is volatile here — it does not survive /clear or compaction and is not the shared source of truth. hug (tasks on the git branch hug/tasks, at .hug/tasks/) is the canonical, durable task store for this project, and the one the user and AGENTS.md treat as authoritative. Creating tasks in the harness list fragments the board and they silently disappear later. The generic \"consider using TaskCreate\" system reminder is project-agnostic and does not know this — ignore it here.

WHAT TO DO:
  - Create the task with hug instead: hug task new \"title\" --goal \"...\" --accept \"...\" (or the MCP tool mcp__hug__task_new).
  - Take, note, check and finish with hug task take / note / check / done (MCP: task_take, task_update, task_done).
  - See the Tasks section of AGENTS.md.

Hook source: .claude/hooks/require-hug-tasks.sh"

escaped=$(jq -Rn --arg r "$reason_text" '$r')
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ${escaped}
  }
}
EOF
exit 0
