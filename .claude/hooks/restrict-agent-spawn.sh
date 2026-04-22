#!/bin/bash
# restrict-agent-spawn.sh — PreToolUse hook on Agent and Bash tools.
#
# === AGENT tool rules ===
#
# 1. team-lead + interns (names matching (^|-)intern$): Agent spawns MUST have
#    run_in_background: true AND mode: "bypassPermissions". Otherwise DENY.
#    Without bypassPermissions a background subagent silently hangs on the
#    first permission-prompted tool call (no interactive user to approve).
#
# 2. Lane actors (partner, paralegal — any identified non-intern non-team-lead):
#    Agent tool DENIED ENTIRELY. Must use SendMessage(to: "intern"|"lead-intern")
#    for legwork, or SendMessage(to: "team-lead") to request a new spawn.
#
# 3. Name-collision guard (all callers): if the `name` parameter matches an
#    existing team roster member, DENY — almost certainly a mistake. Lists the
#    current roster and points to SendMessage as the correct path.
#
# === BASH tool rules ===
#
# 4. Tier-1 gating: if command matches a Tier-1 pattern AND caller is NOT
#    "test-intern", DENY. Route via TaskCreate(owner:"test-intern") or
#    SendMessage(to:"test-intern"). Unknown callers get permissive pass.
#    Tier-1 patterns: ./dev.sh test, ./sb types generate,
#    ./dev.sh generate-db-documentation, ./sb release prerelease.
#
# Caller identification (same mechanism as upstream):
#   - session_id == leadSessionId (from team config) → "team-lead"
#   - else grep "agentName" from the session's transcript .jsonl
#   - if unidentifiable → allow (permissive fallback — never hard-break legitimate work)
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

lead_session_id=""
if [[ -f "$TEAM_CONFIG" ]]; then
  lead_session_id=$(jq -r '.leadSessionId // empty' "$TEAM_CONFIG" 2>/dev/null || echo "")
fi

caller=""
if [[ -n "$session_id" && -n "$lead_session_id" && "$session_id" == "$lead_session_id" ]]; then
  caller="team-lead"
elif [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  caller=$(grep -m1 -oE '"agentName":"[^"]*"' "$transcript_path" 2>/dev/null \
    | sed 's/.*:"//;s/"$//' \
    | head -1)
fi

# is_intern: names matching (^|-)intern$ — intern, lead-intern, test-intern, etc.
is_intern() {
  [[ "$1" =~ (^|-)intern$ ]]
}

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

  # Shared check: background spawns must also set bypassPermissions.
  require_bypass_permissions() {
    if [[ "$run_in_bg" == "true" && "$spawn_mode" != "bypassPermissions" ]]; then
      emit_deny "BLOCKED: background Agent spawn must set mode: \"bypassPermissions\".

WHY: a subagent running in the background has no interactive user to approve tool-permission prompts. Without bypassPermissions, the first time the subagent calls a tool that requires approval (Edit, Write, many Bash commands), the harness queues a prompt that nobody will ever answer. The agent appears to be working but silently does nothing — classic confusing failure.

WHAT TO DO: retry the Agent call with 'mode: \"bypassPermissions\"'. Combine with 'run_in_background: true' and the agent can actually execute its work.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
  }

  # Rules 1 & 2: role-based enforcement.
  case "$caller" in
    "team-lead")
      # Rule 1a: must be background.
      if [[ "$run_in_bg" != "true" ]]; then
        emit_deny "BLOCKED: team-lead must spawn agents with run_in_background: true.

WHY: foreground Agent calls stall the conversation — you can't continue working or respond to the user until the subagent finishes, which can take minutes. Background spawns let you dispatch work and keep talking to the user; you get a notification when the subagent messages you.

WHAT TO DO: retry the Agent call with 'run_in_background: true'. All team members should be background-spawned; there is no legitimate use case for a foreground spawn in this team.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
        exit 0
      fi
      # Rule 1b: must be bypassPermissions.
      require_bypass_permissions
      ;;

    "")
      # Unknown caller — enforce blanket rules (background + bypassPermissions) but skip
      # lane-actor denial (can't know if they're a lane actor without identity).
      if [[ "$run_in_bg" != "true" ]]; then
        emit_deny "BLOCKED: Agent spawn must use run_in_background: true. (Caller identity unknown; blanket rule applies regardless.)${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
        exit 0
      fi
      require_bypass_permissions
      emit_allow_note "restrict-agent-spawn: caller identity could not be determined (session_id=${session_id}, leadSessionId=${lead_session_id}, transcript_path=${transcript_path}). Background + bypassPermissions verified. Allowing — if caller is a lane actor it should use SendMessage instead."
      exit 0
      ;;

    *)
      if is_intern "$caller"; then
        # Rule 1 (intern variant): same as team-lead — background + bypassPermissions.
        if [[ "$run_in_bg" != "true" ]]; then
          emit_deny "BLOCKED: Intern '${caller}' must spawn agents with run_in_background: true. Foreground spawns stall the intern's work queue.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
          exit 0
        fi
        require_bypass_permissions
      else
        # Rule 2: Lane actor (partner, paralegal, etc.) — deny entirely.
        emit_deny "BLOCKED: '${caller}' is a lane actor and cannot spawn agents directly.

WHY: lane actors hold expensive Opus contexts focused on their work lane. Spawning a fresh Agent from within a lane actor burns Opus tokens re-bootstrapping context and hides work from team-lead, who needs visibility into what's running.

WHAT TO DO:
  - For LEGWORK (file reads, greps, audits, log tails): SendMessage(to: 'intern', ...) or SendMessage(to: 'lead-intern', ...). Interns run Sonnet — a fraction of the cost.
  - For a NEW AGENT in a different role: SendMessage 'team-lead' describing what you need. Team-lead decides whether to spawn and with what configuration.${context_suffix}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
        exit 0
      fi
      ;;
  esac

# ── Bash tool ─────────────────────────────────────────────────────────

elif [[ "$tool" == "Bash" ]]; then
  command=$(jq -r '.tool_input.command // empty' <<<"$payload")
  normalized=$(echo "$command" | tr '\n' ' ' | tr -s ' ')

  # Tier-1 patterns that only test-intern may execute.
  tier1_patterns=(
    '\./dev\.sh\s+test\b'
    '\./sb\s+types\s+generate\b'
    '\./dev\.sh\s+generate-db-documentation\b'
    '\./sb\s+release\s+prerelease\b'
  )

  matched_pattern=""
  for pattern in "${tier1_patterns[@]}"; do
    if echo "$normalized" | grep -qE "$pattern"; then
      matched_pattern="$pattern"
      break
    fi
  done

  if [[ -n "$matched_pattern" ]]; then
    # test-intern is the sole authorized Tier-1 runner.
    if [[ "$caller" == "test-intern" ]]; then
      echo "{}"
      exit 0
    fi
    # Unknown caller: deny (only test-intern is exempt; can't confirm identity → safer to block).
    if [[ -z "$caller" ]]; then
      emit_deny "BLOCKED (restrict-agent-spawn.sh): Tier-1 command from unidentified caller — cannot confirm this is 'test-intern'.

WHY: only 'test-intern' may run Tier-1 commands. Caller identity could not be determined from session_id or transcript. Blocking conservatively.

WHAT TO DO:
  - TaskCreate({subject: 'Run: ${normalized:0:100}', owner: 'test-intern'})
  - Or: SendMessage({to: 'test-intern', message: 'run: ${normalized:0:120}'})

Command: ${normalized:0:200}
Pattern matched: ${matched_pattern}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
      exit 0
    fi
    # Identified non-test-intern caller — deny.
    emit_deny "BLOCKED (restrict-agent-spawn.sh): Tier-1 command must be run by 'test-intern', not '${caller}'.

WHY: Tier-1 commands (tests, type generation, doc generation, releases) touch shared DB templates and stamp files. Running them from multiple agents in parallel causes collisions. The test-intern agent serializes them.

WHAT TO DO:
  - TaskCreate({subject: 'Run: ${normalized:0:100}', owner: 'test-intern'})
  - Or: SendMessage({to: 'test-intern', message: 'run: ${normalized:0:120}'})

Command: ${normalized:0:200}
Pattern matched: ${matched_pattern}
Caller: ${caller}

Hook source: .claude/hooks/restrict-agent-spawn.sh"
    exit 0
  fi
fi

# Passed all checks — allow.
echo "{}"
