#!/bin/bash
# require-backlog-slug.sh — PreToolUse hook on mcp__backlog__task_create and
# mcp__backlog__task_edit.
#
# Requires every Backlog.md task title to begin with a slug prefix:
#   slug-for-issue: Description body
#
# Slug rules (same shape as the retired require-task-slug):
#   • Starts with a lowercase letter (a-z)
#   • Then 2-30 chars of a-z / 0-9 / hyphen  (3-31 total)
#   • Immediately followed by ": " (colon + space)
#   • Then a non-empty description body
#
# WHY: Backlog.md is now the team's task board (the harness Task* list is blocked
# by require-backlog-tasks.sh). The user reads chat, not the board UI, and commit
# messages cannot carry a bare ticket number — the slug is the readable, stable
# handle for BOTH conversation and git history. "STATBUS-017" is opaque;
# "rune-wedge: …" is not. Enforced structurally, not by convention (conventions
# get dropped; there is too much else to track).
#
# Scope: task_create's title is always checked; task_edit's title is checked only
# when the edit sets it (a rename) — edits that touch only status/notes/assignee
# pass straight through.
#
# Parameterisation:
#   HOOK_ENABLED_REQUIRE_BACKLOG_SLUG — set to 0 to disable (default: 1 = active)

set -euo pipefail

HOOK_ENABLED="${HOOK_ENABLED_REQUIRE_BACKLOG_SLUG:-1}"
if [[ "$HOOK_ENABLED" != "1" ]]; then
  echo "{}"
  exit 0
fi

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

case "$tool" in
  mcp__backlog__task_create | mcp__backlog__task_edit) : ;;
  *) echo "{}"; exit 0 ;;
esac

title=$(jq -r '.tool_input.title // empty' <<<"$payload")

# An edit that does not set a title (status/notes/assignee only) — and the
# tool-level "title required" check for create — leave nothing for us to inspect.
if [[ -z "$title" ]]; then
  echo "{}"
  exit 0
fi

emit_deny() {
  local _reason="$1" _escaped
  _escaped=$(jq -Rn --arg r "$_reason" '$r')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ${_escaped}
  }
}
EOF
}

# Slug = [a-z][a-z0-9-]{2,30} immediately followed by ": " and a non-empty body.
if [[ ! "$title" =~ ^[a-z][a-z0-9-]{2,30}:[[:space:]].+ ]]; then
  emit_deny "BLOCKED (require-backlog-slug.sh): Backlog task title \"${title:0:100}\" must start with a slug prefix.

WHY: Backlog.md is the team's task board (the harness Task* list is blocked here). The user reads chat, not the board UI, and commits cannot carry a bare ticket number — the slug is the readable, stable handle for conversation AND git history. \"STATBUS-017\" is opaque; \"rune-wedge: …\" is not.

REQUIRED FORMAT:
  slug-for-issue: Description of the task

Slug rules:
  • Start with a lowercase letter (a-z)
  • Characters: lowercase a-z, digits 0-9, hyphen (-)
  • Length: 3-31 characters total
  • Followed immediately by \": \" (colon + space)
  • Then a non-empty description body

Good examples:
  rune-wedge: route schema-skew migrate-up failure to recovery
  install-recovery: drive scenarios green on Hetzner VMs
  enforce-team-name: flag-gate the require-teaming rule

Bad (all rejected):
  \"Fix the rune wedge\"     — no slug prefix
  \"Rune: fix it\"           — uppercase first char
  \"ab: too short\"          — slug under 3 chars
  \"good-slug:no-space\"     — missing space after colon

Tool: ${tool}

Hook source: .claude/hooks/require-backlog-slug.sh"
  exit 0
fi

echo "{}"
