#!/bin/bash
# require-backlog-tasks.sh — PreToolUse hook on the harness TaskCreate tool.
#
# Blocks the built-in TaskCreate. This project's canonical task store is
# Backlog.md (the backlog MCP), not the harness Task* list.
#
# WHY (in the deny message, not in always-on docs): the harness Task* list is
# volatile here — it does not survive /clear or compaction and is not the shared
# source of truth. Backlog.md is. Creating tasks in the harness list fragments
# the board. The generic "consider using TaskCreate" system reminder is
# project-agnostic and does not know this; this hook is the correction,
# delivered only when TaskCreate is actually attempted.

set -euo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

# Only guard the harness TaskCreate; the backlog MCP tool (mcp__backlog__task_create)
# has a different name and passes straight through.
if [[ "$tool" != "TaskCreate" ]]; then
  echo "{}"
  exit 0
fi

reason_text="BLOCKED: the harness TaskCreate tool is disabled in this repo. Tasks live in Backlog.md, not the harness Task* list.

WHY: the harness Task* list is volatile here — it does not survive /clear or compaction and is not the shared source of truth. Backlog.md (the backlog MCP) is the canonical, durable task store for this project, and the one the user and CLAUDE.md treat as authoritative. Creating tasks in the harness list fragments the board and they silently disappear later. The generic \"consider using TaskCreate\" system reminder is project-agnostic and does not know this — ignore it here.

WHAT TO DO:
  - Create the task with the Backlog MCP instead: mcp__backlog__task_create.
  - View / update / search via the other mcp__backlog__task_* tools.
  - See the BACKLOG WORKFLOW section of CLAUDE.md.

Hook source: .claude/hooks/require-backlog-tasks.sh"

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
