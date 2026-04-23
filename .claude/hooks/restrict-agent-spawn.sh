#!/bin/bash
# restrict-agent-spawn.sh — PreToolUse hook on Agent and Bash tools.
#
# Team roles on this project: foreman (team-lead), engineer, mechanic,
# tester, operator. See .claude/team/README.md for the full roster and
# the cost-aware delegation pattern.
#
# === AGENT tool rules ===
#
# 1. Only the foreman may spawn agents. All other roles → DENY. Use
#    SendMessage to reach an existing teammate, or ask the foreman to
#    spawn a new one.
#
# 2. Foreman-spawned agents must set run_in_background: true AND
#    mode: "bypassPermissions". Without bypassPermissions, a background
#    subagent silently hangs on the first permission-prompted tool call
#    (no interactive user to approve).
#
# 3. Name-collision guard (all callers): if the `name` parameter matches
#    an existing team roster member, DENY — almost certainly a mistake.
#
# === BASH tool rules ===
#
# 4. `./dev.sh test …` → only the tester may run it. Concurrent test
#    runs from different agents corrupt shared DB templates.
#
# 5. `./sb release prerelease` → only the foreman may run it. Release
#    commands modify tags and branches — foreman's authority.
#
# Caller identification:
#   - session_id == leadSessionId (from team config) → "foreman"
#   - else grep agentName from the session's transcript .jsonl
#   - if unidentifiable → permissive fallback (never hard-break legitimate work)
#
# Parameterization:
#   CLAUDE_TEAM_CONFIG — full path to team config (overrides constructed path; used by tests)
#   CLAUDE_TEAM_NAME   — team name inside ~/.claude-veridit/teams/ (default: team)

set -euo pipefail

TEAM_CONFIG="${CLAUDE_TEAM_CONFIG:-${HOME}/.claude-veridit/teams/${CLAUDE_TEAM_NAME:-team}/config.json}"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "Agent" && "$tool" != "Bash" ]]; then
  echo "{}"
  exit 0
fi

session_id=$(jq -r '.session_id // empty' <<<"$payload")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$payload")

# ── helpers ──

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

emit_allow_note() {
  local _note="$1"
  local _escaped
  _escaped=$(jq -Rn --arg r "$_note" '$r')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": ${_escaped}
  }
}
EOF
}

# ── identify caller ──
# The harness concept is "team-lead"; in our vocabulary that's the foreman.

lead_session_id=""
if [[ -f "$TEAM_CONFIG" ]]; then
  lead_session_id=$(jq -r '.leadSessionId // empty' "$TEAM_CONFIG" 2>/dev/null || echo "")
fi

caller=""
if [[ -n "$session_id" && -n "$lead_session_id" && "$session_id" == "$lead_session_id" ]]; then
  caller="foreman"
elif [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  # `|| true` so a no-match grep (normal case when the session isn't a team
  # member) doesn't trip `pipefail` + `set -e` and exit the hook silently.
  caller=$({ grep -m1 -oE '"agentName":"[^"]*"' "$transcript_path" 2>/dev/null || true; } \
    | sed 's/.*:"//;s/"$//' \
    | head -1)
fi

# ── Agent tool ────────────────────────────────────────────────────────

if [[ "$tool" == "Agent" ]]; then
  run_in_bg=$(jq -r '.tool_input.run_in_background // false' <<<"$payload")
  new_agent_name=$(jq -r '.tool_input.name // ""' <<<"$payload")
  new_model=$(jq -r '.tool_input.model // "(default)"' <<<"$payload")
  spawn_mode=$(jq -r '.tool_input.mode // "default"' <<<"$payload")
  context_suffix=" (caller='${caller}', new agent name='${new_agent_name}', model='${new_model}', run_in_background=${run_in_bg}, mode=${spawn_mode})"

  # Rule 3: Name-collision guard — check before role-based rules.
  if [[ -n "$new_agent_name" && -f "$TEAM_CONFIG" ]]; then
    roster_names=$(jq -r '.members[].name' "$TEAM_CONFIG" 2>/dev/null || true)
    if echo "$roster_names" | grep -qxF "$new_agent_name"; then
      roster_list=$(echo "$roster_names" | sed 's/^/  - /')
      emit_deny "BLOCKED (restrict-agent-spawn.sh): Agent name '${new_agent_name}' already exists in the team roster.

WHY: spawning a new agent with an existing teammate's name throws away warm context, burns cold-start tokens, and creates confusion about which instance will receive SendMessage calls.

WHAT TO DO:
  Use SendMessage to reach the existing agent instead:
    SendMessage({to: '${new_agent_name}', message: '...'})

Current team roster:
${roster_list}

If you genuinely need a brand-new ephemeral agent (not a teammate), give it a unique task-scoped name — e.g. 'researcher', 'scout-install', 'auditor'.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
  fi

  # Shared check: background + bypassPermissions requirement.
  check_bg_and_bypass() {
    if [[ "$run_in_bg" != "true" ]]; then
      emit_deny "BLOCKED: Agent spawn must use run_in_background: true.

WHY: foreground Agent calls stall the conversation — you can't continue working or respond to the user until the subagent finishes, which can take minutes. Background spawns let you dispatch work and keep talking to the user; you get a notification when the subagent messages you.

WHAT TO DO: retry the Agent call with 'run_in_background: true'.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
    if [[ "$spawn_mode" != "bypassPermissions" ]]; then
      emit_deny "BLOCKED: background Agent spawn must set mode: \"bypassPermissions\".

WHY: a subagent running in the background has no interactive user to approve tool-permission prompts. Without bypassPermissions, the first time the subagent calls a tool that requires approval (Edit, Write, many Bash commands), the harness queues a prompt that nobody will ever answer. The agent appears to be working but silently does nothing — classic confusing failure.

WHAT TO DO: retry the Agent call with 'mode: \"bypassPermissions\"'. Combine with 'run_in_background: true' and the agent can actually execute its work.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
  }

  case "$caller" in
    "foreman")
      check_bg_and_bypass
      ;;

    "")
      # Unknown caller — apply background + bypassPermissions blanket rules.
      check_bg_and_bypass
      emit_allow_note "restrict-agent-spawn: caller identity could not be determined (session_id=${session_id}, leadSessionId=${lead_session_id}, transcript_path=${transcript_path}). Background + bypassPermissions verified. Allowing."
      exit 0
      ;;

    *)
      # Rule 1: any identified non-foreman caller — DENY entirely.
      emit_deny "BLOCKED: '${caller}' cannot spawn agents. Only the foreman may spawn.

WHY: the cost-aware team pattern has one spawner (the foreman) and a fixed roster. Spawning from inside a specialist or worker role burns tokens on cold starts and hides work from the foreman.

WHAT TO DO:
  - LEGWORK (reads, greps, SSH, log tails, summaries): SendMessage(to: 'operator', ...).
  - TESTS: SendMessage(to: 'tester', ...) or TaskCreate(owner: 'tester').
  - DIAGNOSIS and targeted fixes: SendMessage(to: 'mechanic', ...).
  - DESIGN or architectural work: SendMessage(to: 'engineer', ...).
  - NEW ROLE (truly needed): SendMessage(to: 'foreman', ...) and ask.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
      ;;
  esac

# ── Bash tool ─────────────────────────────────────────────────────────

elif [[ "$tool" == "Bash" ]]; then
  command=$(jq -r '.tool_input.command // empty' <<<"$payload")
  normalized=$(echo "$command" | tr '\n' ' ' | tr -s ' ')

  # Rule 4: `./dev.sh test …` → only the tester.
  if echo "$normalized" | grep -qE '\./dev\.sh\s+test\b'; then
    if [[ "$caller" == "tester" ]]; then
      echo "{}"
      exit 0
    fi
    if [[ -z "$caller" ]]; then
      emit_deny "BLOCKED (restrict-agent-spawn.sh): test command from unidentified caller — cannot confirm this is the tester.

WHY: only the tester may run \`./dev.sh test\`. Concurrent test runs from different agents corrupt shared DB templates.

WHAT TO DO:
  - TaskCreate({subject: 'slug-for-run: <description>', owner: 'tester'})
  - Or: SendMessage({to: 'tester', message: 'run: ${normalized:0:120}'})

Command: ${normalized:0:200}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
    emit_deny "BLOCKED (restrict-agent-spawn.sh): only the tester may run \`./dev.sh test\`, not '${caller}'.

WHY: concurrent test runs from different agents corrupt shared DB templates. The tester is the single serializer.

WHAT TO DO:
  - TaskCreate({subject: 'slug-for-run: <description>', owner: 'tester'})
  - Or: SendMessage({to: 'tester', message: 'run: ${normalized:0:120}'})

Command: ${normalized:0:200}
Caller: ${caller}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
    exit 0
  fi

  # Rule 5: `./sb release prerelease` → only the foreman.
  if echo "$normalized" | grep -qE '\./sb\s+release\s+prerelease\b'; then
    if [[ "$caller" == "foreman" ]]; then
      echo "{}"
      exit 0
    fi
    if [[ -z "$caller" ]]; then
      emit_deny "BLOCKED (restrict-agent-spawn.sh): release command from unidentified caller — cannot confirm this is the foreman.

WHY: only the foreman may run release commands. They modify tags and branches — foreman's authority.

WHAT TO DO: SendMessage(to: 'foreman') and ask them to run it.

Command: ${normalized:0:200}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
    emit_deny "BLOCKED (restrict-agent-spawn.sh): only the foreman may run \`./sb release prerelease\`, not '${caller}'.

WHY: release commands are foreman's authority — they modify tags and branches.

WHAT TO DO: SendMessage({to: 'foreman', message: 'please run: ${normalized:0:120}'}).

Command: ${normalized:0:200}
Caller: ${caller}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
    exit 0
  fi
fi

# Passed all checks — allow.
echo "{}"
