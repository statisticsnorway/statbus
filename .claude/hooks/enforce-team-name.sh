#!/bin/bash
# enforce-team-name.sh — PreToolUse hook on TeamCreate and Agent.
#
# Guards against the generic-team-name collision. A team name is a single
# GLOBAL namespace (${CLAUDE_CONFIG_DIR}/teams/<name>/). When two Claude Code
# sessions on the same machine both create a team named "team", they share
# that directory, clobber each other's roster, and cross-deliver messages.
# (This bit us 2026-06-09: a frogs session and the statbus session both used
# "team"; the statbus TeamCreate overwrote the frogs roster.) The fix: declare
# a project-specific team name once in .claude/team.name, and enforce it here.
#
# RULE: TeamCreate.team_name and Agent.team_name MUST equal the project's
# declared team name. Mismatch -> DENY, naming the correct value.
#
# Expected-name source (precedence — mirrors restrict-agent-spawn.sh's
# resolve_team_name so the two hooks agree):
#   CLAUDE_TEAM_NAME env  -> explicit, enforced
#   .claude/team.name     -> project-local one-line file, enforced
#   (neither)             -> intended name unknown -> ALLOW (permissive; never
#                            hard-break a project that has not declared one)
#
# Copyable VERBATIM across projects: each project declares its own name in
# .claude/team.name (this repo: "statbus"; the frogs repo: "frogs"). No edit
# to this script is needed when copying — only the team.name file differs.

set -euo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

# Only gate the team-creating / team-joining tools; everything else passes.
if [[ "$tool" != "TeamCreate" && "$tool" != "Agent" ]]; then
  echo "{}"
  exit 0
fi

team_name=$(jq -r '.tool_input.team_name // empty' <<<"$payload")

# An Agent spawn with no team_name is a plain subagent (not joining a team) —
# nothing to enforce.
if [[ -z "$team_name" ]]; then
  echo "{}"
  exit 0
fi

# Resolve the declared team name (env > .claude/team.name).
expected=""
if [[ -n "${CLAUDE_TEAM_NAME:-}" ]]; then
  expected="$CLAUDE_TEAM_NAME"
elif [[ -f ".claude/team.name" ]]; then
  expected=$(head -1 ".claude/team.name" | tr -d '[:space:]' || true)
fi

# No declared name -> cannot enforce -> allow (permissive fallback).
if [[ -z "$expected" ]]; then
  echo "{}"
  exit 0
fi

if [[ "$team_name" != "$expected" ]]; then
  reason="BLOCKED (enforce-team-name.sh): team_name '${team_name}' is not this project's team.

WHY: the team name is a single GLOBAL namespace (\${CLAUDE_CONFIG_DIR}/teams/<name>/). A generic or wrong name collides with other Claude Code sessions on this machine — they share the directory, clobber each other's roster, and cross-deliver messages. This project's team is declared in .claude/team.name.

WHAT TO DO: use team_name: \"${expected}\".
  TeamCreate({team_name: \"${expected}\", ...})
  Agent({..., team_name: \"${expected}\", name: \"<role>\"})

Declared team name (.claude/team.name): ${expected}
You passed: ${team_name}
Tool: ${tool}

Hook source: .claude/hooks/enforce-team-name.sh"
  _escaped=$(jq -Rn --arg r "$reason" '$r')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ${_escaped}
  }
}
EOF
  exit 0
fi

# team_name matches the declared name — allow.
echo "{}"
