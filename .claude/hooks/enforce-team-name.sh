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
#   - NAME MATCH (always, when a name is declared): TeamCreate/Agent team_name
#     MUST equal the declared name; mismatch -> DENY.
#   - TEAM REQUIRED (opt-in): in strict mode, a MISSING team_name on
#     TeamCreate/Agent -> DENY (no un-teamed background agents). Default OFF:
#     an Agent with no team_name passes as a plain subagent — this hook is a
#     collision guard, not a "must be teamed" guarantee.
#
# SCOPE NOTE: statbus runs PERMISSIVE — its "only the foreman may spawn agents"
# guarantee lives in restrict-agent-spawn.sh, so this hook need only stop name
# collisions. frogs does NOT copy restrict-agent-spawn.sh and requires every
# agent to be teamed, so frogs runs STRICT. One identical file serves both via
# the flag below — copyable verbatim; only the per-project config differs.
#
# CONFIG (paths resolve against $CLAUDE_PROJECT_DIR, set by Claude Code for
# hooks; falls back to CWD so the test harness can point it at a fixture):
#   declared name:  CLAUDE_TEAM_NAME env  ->  $proj/.claude/team.name file
#                   (neither -> name unknown -> ALLOW; never hard-break a project
#                   that has not declared a team)
#   strict mode:    CLAUDE_TEAM_REQUIRED env (1/true/yes)  ->  $proj/.claude/team.required file
#                   (neither -> permissive)

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

# No declared name -> cannot enforce -> allow (permissive fallback). This also
# means strict mode is a no-op without a declared name (can't require a team
# that has no name) — the coherent behaviour.
if [[ -z "$expected" ]]; then
  echo "{}"
  exit 0
fi

# Resolve strict mode (env > marker file). Default: permissive.
require_team="false"
case "${CLAUDE_TEAM_REQUIRED:-}" in
  1|true|TRUE|yes|YES) require_team="true" ;;
esac
if [[ "$require_team" != "true" && -f "$proj/.claude/team.required" ]]; then
  require_team="true"
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

# Rule 1 (strict mode only): team_name required — no un-teamed agents.
if [[ -z "$team_name" ]]; then
  if [[ "$require_team" == "true" ]]; then
    emit_deny "BLOCKED (enforce-team-name.sh): ${tool} with no team_name. This repo requires every agent to join the \"${expected}\" team — no un-teamed background agents.

WHY: agents are team members here, not loose subagents — keeping the roster, inboxes, and delegation on one visible registry, and sidestepping the generic-team collision entirely.

WHAT TO DO: pass team_name: \"${expected}\".
  TeamCreate({team_name: \"${expected}\", ...})
  Agent({..., team_name: \"${expected}\", name: \"<role>\"})

Declared team name (.claude/team.name): ${expected}
Tool: ${tool}

Hook source: .claude/hooks/enforce-team-name.sh"
    exit 0
  fi
  # Permissive: a plain subagent with no team is fine.
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
