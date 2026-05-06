#!/bin/bash
# require-task-slug.sh — PreToolUse hook on TaskCreate + TaskUpdate.
#
# Requires every task subject to begin with a slug prefix:
#   slug-for-issue: description body
#
# Slug constraints:
#   • Starts with a lowercase letter (a-z)
#   • Followed by 2-30 chars of a-z / 0-9 / hyphen  (total 3-31 chars)
#   • Immediately followed by ": " (colon + space)
#   • Then a non-empty description body
#
# WHY: the user cannot see the task list UI — slugs are the only
# conversational handle and the verbatim commit-message handle. A task
# born without one is unaddressable.
#
# Parameterisation:
#   HOOK_ENABLED_REQUIRE_TASK_SLUG — set to 0 to disable (default: 1 = active)
#   CLAUDE_TEAM_NAME               — team name inside ${CLAUDE_CONFIG_DIR}/tasks/
#   .claude/team.name              — project-local team-name fallback (single line)
#
set -euo pipefail

HOOK_ENABLED="${HOOK_ENABLED_REQUIRE_TASK_SLUG:-1}"
if [[ "$HOOK_ENABLED" != "1" ]]; then
  echo "{}"
  exit 0
fi
# ─── live hook logic below ──────────────────────────────────────────────

resolve_team_name() {
  if [[ -n "${CLAUDE_TEAM_NAME:-}" ]]; then
    echo "$CLAUDE_TEAM_NAME"
    return
  fi
  if [[ -f ".claude/team.name" ]]; then
    local _name
    _name=$(head -1 ".claude/team.name" | tr -d '[:space:]' || true)
    if [[ -n "$_name" ]]; then
      echo "$_name"
      return
    fi
  fi
  echo "team"
}

TASK_DIR="${CLAUDE_CONFIG_DIR}/tasks/$(resolve_team_name)"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
input=$(jq -c '.tool_input // empty' <<<"$payload")

case "$tool" in
  TaskCreate | TaskUpdate) : ;;
  *) echo "{}"; exit 0 ;;
esac

subject=$(jq -r '.subject // empty' <<<"$input")

# TaskUpdate without subject change → skip
if [[ -z "$subject" ]]; then
  echo "{}"
  exit 0
fi

# ── helpers ──────────────────────────────────────────────────────────────

emit_deny() {
  local _reason="$1"
  local _escaped
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

# extract_slug <subject> — prints the slug (without colon), or "" if absent/malformed
extract_slug() {
  local _s="$1"
  # Must match: [a-z][a-z0-9-]{2,30}: .+
  if [[ "$_s" =~ ^([a-z][a-z0-9-]{2,30}):[[:space:]].+ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# collect_existing_slugs [exclude_id] — newline-separated slugs from TASK_DIR
collect_existing_slugs() {
  local _exclude="${1:-}"
  [[ -d "$TASK_DIR" ]] || return 0
  local _f _file_id _fsubj _fslug
  for _f in "$TASK_DIR"/*.json; do
    [[ -f "$_f" ]] || continue
    _file_id=$(basename "$_f" .json)
    [[ -n "$_exclude" && "$_file_id" == "$_exclude" ]] && continue
    _fsubj=$(jq -r '.subject // empty' "$_f" 2>/dev/null || true)
    _fslug=$(extract_slug "$_fsubj")
    [[ -n "$_fslug" ]] && echo "$_fslug"
  done
}

DENY_TEMPLATE='BLOCKED: task subject must start with a slug prefix.

WHY: the user cannot see the task list UI — slugs are the only
conversational handle and the verbatim commit-message handle.
A task born without one is unaddressable in conversation and in git history.

REQUIRED FORMAT:
  slug-for-issue: description of what to do

Slug rules:
  • Must start with a lowercase letter (a-z)
  • Characters: lowercase a-z, digits 0-9, hyphen (-)
  • Length: 3-31 characters total
  • Followed immediately by ": " (colon + space)
  • Then a non-empty description body

Good examples:
  require-slug-hook: enforce slug on TaskCreate
  rune-upgrade: validate NO upgrade to rc.53 via standalone.sh
  stats-null-fix: derive_statistical_history refresh NULL-summary rows

Bad examples (all rejected):
  "Fix the bug"                  — no slug prefix
  "[fix-bug] Fix the bug"        — wrong format (brackets not colons)
  "Fix: fix the bug"             — uppercase first char
  "ab: too short"                — slug under 3 chars
  "-bad: leading hyphen"         — must start with letter
  "good-slug:no-space"           — missing space after colon

Hook source: .claude/hooks/require-task-slug.sh'

# ── validate subject has a well-formed slug ───────────────────────────────

slug=$(extract_slug "$subject")

if [[ -z "$slug" ]]; then
  emit_deny "BLOCKED: subject \"${subject:0:100}\" does not match the required slug format.

${DENY_TEMPLATE}"
  exit 0
fi

# ── uniqueness check ──────────────────────────────────────────────────────

task_id=$(jq -r '.taskId // empty' <<<"$input")
existing=$(collect_existing_slugs "$task_id")

if [[ -n "$existing" ]] && echo "$existing" | grep -Fxq "$slug" 2>/dev/null; then
  emit_deny "BLOCKED: slug \"${slug}\" is already used by another task.

Choose a distinct slug. Currently used slugs:
$(echo "$existing" | sort | sed 's/^/  /')

${DENY_TEMPLATE}"
  exit 0
fi

echo "{}"
