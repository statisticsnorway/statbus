#!/bin/bash
# require-bash-background.sh — PreToolUse hook on the Bash tool.
# Statbus project variant.
#
# Blocks foreground Bash calls that look long-running. The rule applies
# to everyone in the campaign: main session, scouts, lane actors.
#
# WHY: foreground long-running Bash calls stall the conversation. The
# caller (me or a subagent) cannot continue work, cannot respond to the
# user, and cannot start other parallel tasks until the command returns.
# Backgrounded Bash (run_in_background: true) still gives you the output
# — you can read it via BashOutput or wait for completion — but keeps
# the conversation flow alive.
#
# Policy:
#   1. If command matches a known long-running pattern → require
#      run_in_background: true.
#   2. If timeout > 30000 ms (the caller expects it to take > 30s) →
#      same rule.
#   3. If run_in_background: true is already set → allow.
#   4. Otherwise → allow (command doesn't look long-running).
#
# Patterns are conservative (prefer false-negative over false-positive).
# Add new patterns when a specific long command repeatedly stalls
# conversations — the fix is narrow and data-driven.

set -euo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")

if [[ "$tool" != "Bash" ]]; then
  echo "{}"
  exit 0
fi

command=$(jq -r '.tool_input.command // empty' <<<"$payload")
run_in_bg=$(jq -r '.tool_input.run_in_background // false' <<<"$payload")
timeout_ms=$(jq -r '.tool_input.timeout // 0' <<<"$payload")

# Already background → nothing to do.
if [[ "$run_in_bg" == "true" ]]; then
  echo "{}"
  exit 0
fi

# ── long-running detection ──

# Normalize command: single-line, squeeze whitespace for matching.
normalized=$(echo "$command" | tr '\n' ' ' | tr -s ' ')

is_long() {
  local cmd="$1"

  # Explicit long timeout set by the caller — they know it's long.
  if (( timeout_ms > 30000 )); then
    echo "timeout=${timeout_ms}ms (> 30s)"
    return 0
  fi

  # Known slow tool invocations (regex, with word boundaries).
  # Format: "label|regex"
  local patterns=(
    './dev.sh test|\./dev\.sh\s+test\b'
    './dev.sh create-db/recreate/delete-db|\./dev\.sh\s+(create-db|recreate-database|delete-db)\b'
    './dev.sh update-snapshot|\./dev\.sh\s+update-snapshot\b'
    './dev.sh generate-db-documentation|\./dev\.sh\s+generate-db-documentation\b'
    './sb install|\./sb\s+install\b'
    './sb upgrade apply|\./sb\s+upgrade\s+apply\b'
    './sb release prerelease|\./sb\s+release\s+prerelease\b'
    './sb db restore/dump|\./sb\s+db\s+(restore|dump)\b'
    'pnpm run build/test|\bpnpm\s+(run\s+(build|test)|install|ci)\b'
    'docker compose logs -f|\bdocker\s+compose\s+logs\b.*\s-f\b'
    'tail -f|\btail\s+-f\b'
    'watch|(^|[ ;|&])watch\s+'
    'nice prefix|(^|[ ;|&])nice\s+'
  )

  for entry in "${patterns[@]}"; do
    local label="${entry%%|*}"
    local regex="${entry#*|}"
    if echo "$cmd" | grep -qE "$regex"; then
      echo "matches '${label}'"
      return 0
    fi
  done

  # docker compose up without -d — foreground means it follows logs.
  # docker compose up -d is detached and returns immediately.
  if echo "$cmd" | grep -qE '\bdocker\s+compose\s+up\b' && \
     ! echo "$cmd" | grep -qE '(^|\s)-d(\s|$)'; then
    echo "matches 'docker compose up (no -d)'"
    return 0
  fi

  return 1
}

if reason=$(is_long "$normalized"); then
  # Deny with guidance.
  reason_text="BLOCKED: Foreground Bash command looks long-running (${reason}).

WHY: foreground long-running commands stall the conversation. You can't continue working, respond to the user, or dispatch parallel tasks until the command finishes.

WHAT TO DO:
  1. Retry with 'run_in_background: true'. This spawns the command as a background job — the conversation keeps moving.
  2. Read the output when you need it:
       - With BashOutput tool (pulls stdout/stderr from the background job).
       - If you need to wait for completion before proceeding, the ScheduleWakeup tool lets you check back after a delay, OR just dispatch other work and poll.
  3. For truly quick probes (< 10s) you don't expect to block, this hook does not fire — proceed foreground. If a command you consider quick is matched, expand the pattern list carefully (data-driven).

Command that tripped this rule:
  ${normalized:0:200}

Hook source: .claude/hooks/require-bash-background.sh"

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
fi

# Default: allow (not matched as long-running).
echo "{}"
