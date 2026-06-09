#!/bin/bash
# enforce-team-name.sh — PreToolUse hook on TeamCreate and Agent.
#
# Guards the Claude Code team name against the generic-"team" collision. A team
# name is a single GLOBAL namespace (${CLAUDE_CONFIG_DIR}/teams/<name>/); two
# sessions on one machine both creating "team" share that directory, clobber
# each other's roster, and cross-deliver messages (this bit statbus + frogs on
# 2026-06-09: a statbus TeamCreate overwrote the frogs roster).
#
# TWO RULES:
#   - TEAM REQUIRED (default): a MISSING team_name on TeamCreate/Agent -> DENY.
#     Every agent is a team member; no loose un-teamed background agents. Strict
#     is the DEFAULT so the safe behaviour can never be silently lost — forget
#     the config and you fail safe (strict), not loose. A project with a genuine
#     un-teamed spawn path OPTS OUT with a deliberate, committed marker.
#   - NAME MATCH (always, when a name is declared): team_name MUST equal the
#     declared name; mismatch -> DENY.
#
# CONFIG (paths resolve against $CLAUDE_PROJECT_DIR, set by Claude Code for
# hooks; falls back to CWD so the test harness can point it at a fixture):
#   declared name:  CLAUDE_TEAM_NAME env  ->  $proj/.claude/team.name file
#                   (neither -> name unknown -> ALLOW; never hard-break a project
#                   that has not declared a team at all)
#   opt OUT of required: CLAUDE_TEAM_OPTIONAL env (1/true/yes)
#                        ->  $proj/.claude/team.optional file
#                   (neither -> required, the default)
#
# Copyable verbatim across projects: only the per-project .claude/team.name (and,
# for a project that opts out, .claude/team.optional) differ.

set -euo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

# Only gate the team-creating / team-joining tools; everything else passes.
if [[ "$tool" != "TeamCreate" && "$tool" != "Agent" ]]; then
  echo "{}"
  exit 0
fi

proj="${CLAUDE_PROJECT_DIR:-.}"

# Resolve the declared team name (env > project-local file).
expected=""
if [[ -n "${CLAUDE_TEAM_NAME:-}" ]]; then
  expected="$CLAUDE_TEAM_NAME"
elif [[ -f "$proj/.claude/team.name" ]]; then
  expected=$(head -1 "$proj/.claude/team.name" | tr -d '[:space:]' || true)
fi

# No declared name -> cannot enforce -> allow (never hard-break a project that
# has not declared a team at all). Also makes "required" a no-op without a name.
if [[ -z "$expected" ]]; then
  echo "{}"
  exit 0
fi

# Teaming is REQUIRED by default. Opt OUT via env or a committed marker file.
require_team="true"
case "${CLAUDE_TEAM_OPTIONAL:-}" in
  1|true|TRUE|yes|YES) require_team="false" ;;
esac
if [[ "$require_team" == "true" && -f "$proj/.claude/team.optional" ]]; then
  require_team="false"
fi

team_name=$(jq -r '.tool_input.team_name // empty' <<<"$payload")

emit_deny() {
  local _r="$1" _e
  _e=$(jq -Rn --arg r "$_r" '$r')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ${_e}
  }
}
EOF
}

# Rule 1 (default): team_name required — no un-teamed agents.
if [[ -z "$team_name" ]]; then
  if [[ "$require_team" == "true" ]]; then
    emit_deny "BLOCKED (enforce-team-name.sh): ${tool} with no team_name. Every agent must join the \"${expected}\" team — no un-teamed background agents.

WHY: agents are team members here, not loose subagents — keeping the roster, inboxes, and delegation on one visible registry, and sidestepping the generic-team collision entirely. (A project with a genuine un-teamed spawn path opts out with .claude/team.optional.)

WHAT TO DO: pass team_name: \"${expected}\".
  TeamCreate({team_name: \"${expected}\", ...})
  Agent({..., team_name: \"${expected}\", name: \"<role>\"})

Declared team name (.claude/team.name): ${expected}
Tool: ${tool}

Hook source: .claude/hooks/enforce-team-name.sh"
    exit 0
  fi
  # Opted out: a plain subagent with no team is allowed.
  echo "{}"
  exit 0
fi

# Rule 2 (always): team_name must equal the declared name.
if [[ "$team_name" != "$expected" ]]; then
  emit_deny "BLOCKED (enforce-team-name.sh): team_name '${team_name}' is not this project's team.

WHY: the team name is a single GLOBAL namespace (\${CLAUDE_CONFIG_DIR}/teams/<name>/). A generic or wrong name collides with other Claude Code sessions on this machine — they share the directory, clobber each other's roster, and cross-deliver messages. This project's team is declared in .claude/team.name.

WHAT TO DO: use team_name: \"${expected}\".
  TeamCreate({team_name: \"${expected}\", ...})
  Agent({..., team_name: \"${expected}\", name: \"<role>\"})

Declared team name (.claude/team.name): ${expected}
You passed: ${team_name}
Tool: ${tool}

Hook source: .claude/hooks/enforce-team-name.sh"
  exit 0
fi

# team_name present and matches the declared name — allow.
echo "{}"
