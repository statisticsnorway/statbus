#!/bin/bash
# route-alias.sh — two-step name handling for SendMessage + Task* tools.
#
#   Step 1: rewrite the agent-facing role name to the harness's internal
#           routing name. In our vocabulary the team-lead is the
#           `foreman`; agents always use `foreman` (or legacy aliases
#           `main` / `counsel`). This step rewrites all three to the
#           harness name `team-lead` so message delivery works.
#   Step 2: validate the final recipient / owner against the team roster.
#           Unknown names are denied with a visible error — converts the
#           claude-code#25135 silent-drop bug into a loud failure.
#
# Both steps are necessary. Step 1 alone restores natural names but
# still lets typos ("fromen", "operatr") silently vanish.
# Step 2 alone would reject `foreman` (not a roster member, the
# harness knows it as `team-lead`) — so the rewrite must run first.
#
# Broadcast (`to: "*"`) is always allowed — no validation needed.
# Empty owner on TaskCreate/TaskUpdate is allowed (not every task op
# touches ownership).
#
# Reference: https://github.com/anthropics/claude-code/issues/25135
#
# Parameterization:
#   CLAUDE_TEAM_CONFIG — full path to team config (overrides constructed path; used by tests)
#   CLAUDE_TEAM_NAME   — team name inside ~/.claude-veridit/teams/ (default: team)

set -euo pipefail

TEAM_CONFIG="${CLAUDE_TEAM_CONFIG:-${HOME}/.claude-veridit/teams/${CLAUDE_TEAM_NAME:-team}/config.json}"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
input=$(jq -c '.tool_input // empty' <<<"$payload")

# ── helpers ──

emit_rewrite() {
  local _tool="$1" _field="$2" _orig="$3" _updated="$4"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "route-alias: canonicalised ${_tool} ${_field} '${_orig}' -> 'team-lead' (harness routing name)",
    "updatedInput": ${_updated}
  }
}
EOF
}

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

get_roster() {
  if [[ -f "$TEAM_CONFIG" ]]; then
    jq -r '.members[].name' "$TEAM_CONFIG" 2>/dev/null | sort -u
  fi
}

is_in_roster() {
  local _name="$1"
  local _roster
  _roster=$(get_roster)
  [[ -z "$_roster" ]] && return 0  # empty / unreadable roster → allow everything
  grep -Fxq "$_name" <<<"$_roster"
}

format_roster_inline() {
  local _roster
  _roster=$(get_roster)
  if [[ -z "$_roster" ]]; then
    echo "(roster unreadable — ${TEAM_CONFIG})"
  else
    echo "$_roster" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g'
  fi
}

# is_alias: returns 0 (true) if the name aliases the team-lead (the foreman).
# Agents use `foreman`; legacy aliases `main` and `counsel` also accepted.
is_alias() {
  [[ "$1" == "foreman" || "$1" == "main" || "$1" == "counsel" ]]
}

# ── main ──

case "$tool" in
  SendMessage)
    recipient=$(jq -r '.to // empty' <<<"$input")

    # Narrow bypass: shutdown-protocol messages (shutdown_request,
    # shutdown_response) must reach the addressed agent verbatim. Validate
    # the recipient exists in the roster but do NOT rewrite aliases — the
    # caller must use the canonical name for shutdown traffic.
    msg_type=$(jq -r 'if (.message | type) == "object" then (.message.type // "") else "" end' <<<"$input")
    if [[ "$msg_type" == "shutdown_request" || "$msg_type" == "shutdown_response" ]]; then
      if [[ "$recipient" == "*" ]]; then
        echo "{}"
        exit 0
      fi
      if is_in_roster "$recipient"; then
        echo "{}"
        exit 0
      fi
      roster_inline=$(format_roster_inline)
      emit_deny "BLOCKED: no team member named \"${recipient}\" (shutdown-protocol message — aliases not rewritten).

Current roster:
  ${roster_inline}

Use the exact roster name for shutdown_request / shutdown_response.
For the team-lead (foreman), use \"team-lead\" here — this is the one
place shutdown traffic requires the harness name directly.

Hook source: .claude/hooks/route-alias.sh"
      exit 0
    fi

    # Pass 1: alias rewrite
    rewritten_input="$input"
    final_recipient="$recipient"
    if is_alias "$recipient"; then
      rewritten_input=$(jq '.to = "team-lead"' <<<"$input")
      final_recipient="team-lead"
    fi

    # Pass 2: validate
    if [[ "$final_recipient" == "*" ]]; then
      if [[ "$recipient" != "$final_recipient" ]]; then
        emit_rewrite "SendMessage" "to" "$recipient" "$rewritten_input"
      else
        echo "{}"
      fi
      exit 0
    fi

    if is_in_roster "$final_recipient"; then
      if [[ "$recipient" != "$final_recipient" ]]; then
        emit_rewrite "SendMessage" "to" "$recipient" "$rewritten_input"
      else
        echo "{}"
      fi
      exit 0
    fi

    # Unknown recipient — educating deny
    roster_inline=$(format_roster_inline)
    emit_deny "BLOCKED: no team member named \"${recipient}\".

Current roster:
  ${roster_inline}

To reach the foreman, use SendMessage(to: \"foreman\", ...). For any other
role, use the roster name exactly.

Why this hook exists: SendMessage returns success:true for any string,
but only names matching a real member's .name field have a readable
inbox. Typo'd names silently drop — GitHub issue #25135 (closed not
planned). Hence this hook turns the silent drop into a loud typo-catch.

Hook source: .claude/hooks/route-alias.sh"
    exit 0
    ;;

  TaskCreate | TaskUpdate)
    owner=$(jq -r '.owner // empty' <<<"$input")

    # No owner field → skip (not every task op touches ownership)
    if [[ -z "$owner" ]]; then
      echo "{}"
      exit 0
    fi

    # Pass 1: alias rewrite
    rewritten_input="$input"
    final_owner="$owner"
    if is_alias "$owner"; then
      rewritten_input=$(jq '.owner = "team-lead"' <<<"$input")
      final_owner="team-lead"
    fi

    # Pass 2: validate
    if is_in_roster "$final_owner"; then
      if [[ "$owner" != "$final_owner" ]]; then
        emit_rewrite "$tool" "owner" "$owner" "$rewritten_input"
      else
        echo "{}"
      fi
      exit 0
    fi

    # Unknown owner — educating deny
    roster_inline=$(format_roster_inline)
    emit_deny "BLOCKED: no team member named \"${owner}\" (${tool} owner field).

Current roster:
  ${roster_inline}

To assign to the foreman, use owner: \"foreman\". For any other role,
use the roster name exactly (e.g. \"tester\", \"operator\", \"mechanic\",
\"engineer\").

Why this hook exists: an unknown owner orphans the task silently — the
same silent-drop class as GitHub issue #25135. This hook turns it into
a loud typo-catch.

Hook source: .claude/hooks/route-alias.sh"
    exit 0
    ;;
esac

# Fallthrough — tool not matched by this hook
echo "{}"
