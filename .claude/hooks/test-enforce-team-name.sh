#!/bin/bash
# Test suite for .claude/hooks/enforce-team-name.sh
#
#   bash .claude/hooks/test-enforce-team-name.sh
#
# Exit 0: all tests pass. Exit 1: any failure.
#
# Verifies the team-name guard:
#   - TeamCreate.team_name / Agent.team_name MUST equal the declared name
#     (CLAUDE_TEAM_NAME env, else .claude/team.name file); mismatch -> DENY.
#   - env takes precedence over the file.
#   - no declaration -> permissive ALLOW (cannot enforce what isn't declared).
#   - Agent with no team_name (plain subagent) and non-team tools pass through.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/enforce-team-name.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

PASS=0
FAIL=0

# Run the hook from CWD so its relative ".claude/team.name" lookup resolves
# against the fixture (not the real project file). stdin = payload.
run_hook() {
  ( cd "$1" && printf '%s' "$2" | bash "$HOOK" ) 2>/tmp/enforce-team-name-hook.err
}

get_decision() {
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$1" 2>/dev/null || echo "allow"
}

assert_allow() {  # label, cwd, payload
  local label="$1" cwd="$2" payload="$3" out dec
  out=$(run_hook "$cwd" "$payload")
  dec=$(get_decision "$out")
  if [[ "$dec" == "allow" ]]; then
    PASS=$((PASS+1)); printf '[allow OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected allow)\n' "$dec" "$label"
    echo "$out" | head -8 | sed 's/^/    | /'
  fi
}

assert_deny() {  # label, cwd, payload
  local label="$1" cwd="$2" payload="$3" out dec
  out=$(run_hook "$cwd" "$payload")
  dec=$(get_decision "$out")
  if [[ "$dec" == "deny" ]]; then
    PASS=$((PASS+1)); printf '[deny  OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected deny)\n' "$dec" "$label"
    echo "$out" | head -8 | sed 's/^/    | /'
  fi
}

# ── Fixtures ────────────────────────────────────────────────────────────
FX=$(mktemp -d); trap "rm -rf $FX" EXIT
mkdir -p "$FX/declared/.claude"; printf 'statbus\n' > "$FX/declared/.claude/team.name"
mkdir -p "$FX/undeclared"            # no .claude/team.name

# Don't let a caller's shell env leak into the file/undeclared cases.
unset CLAUDE_TEAM_NAME

echo "── .claude/team.name = statbus (file-declared) ─────────────────────"
assert_allow "TeamCreate statbus matches declared file" "$FX/declared" \
  '{"tool_name":"TeamCreate","tool_input":{"team_name":"statbus"}}'
assert_deny  "TeamCreate team mismatches (the collision we are blocking)" "$FX/declared" \
  '{"tool_name":"TeamCreate","tool_input":{"team_name":"team"}}'
assert_deny  "TeamCreate frogs mismatches" "$FX/declared" \
  '{"tool_name":"TeamCreate","tool_input":{"team_name":"frogs"}}'
assert_allow "Agent team_name=statbus matches" "$FX/declared" \
  '{"tool_name":"Agent","tool_input":{"team_name":"statbus","name":"architect"}}'
assert_deny  "Agent team_name=team mismatches" "$FX/declared" \
  '{"tool_name":"Agent","tool_input":{"team_name":"team","name":"architect"}}'
assert_allow "Agent without team_name (plain subagent) passes" "$FX/declared" \
  '{"tool_name":"Agent","tool_input":{"name":"scout","description":"d","prompt":"p"}}'

echo "── CLAUDE_TEAM_NAME env overrides the file ─────────────────────────"
export CLAUDE_TEAM_NAME=envteam
assert_allow "env=envteam: create envteam allowed (file says statbus)" "$FX/declared" \
  '{"tool_name":"TeamCreate","tool_input":{"team_name":"envteam"}}'
assert_deny  "env=envteam: create statbus denied (env wins over file)" "$FX/declared" \
  '{"tool_name":"TeamCreate","tool_input":{"team_name":"statbus"}}'
unset CLAUDE_TEAM_NAME

echo "── no declaration → permissive (cannot enforce) ────────────────────"
assert_allow "undeclared: TeamCreate anything allowed" "$FX/undeclared" \
  '{"tool_name":"TeamCreate","tool_input":{"team_name":"whatever"}}'
assert_allow "undeclared: Agent team_name allowed" "$FX/undeclared" \
  '{"tool_name":"Agent","tool_input":{"team_name":"whatever","name":"x"}}'

echo "── non-gated tools pass through ────────────────────────────────────"
assert_allow "Bash is not gated" "$FX/declared" \
  '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
assert_allow "TaskCreate is not gated" "$FX/declared" \
  '{"tool_name":"TaskCreate","tool_input":{"subject":"s","description":"d"}}'
assert_allow "SendMessage is not gated" "$FX/declared" \
  '{"tool_name":"SendMessage","tool_input":{"to":"operator","summary":"s","message":"m"}}'

# ── Report ────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
echo "────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
  echo "ALL GREEN: $PASS / $TOTAL tests passed"
  exit 0
else
  echo "FAILED: $FAIL / $TOTAL tests failed ($PASS passed)"
  exit 1
fi
