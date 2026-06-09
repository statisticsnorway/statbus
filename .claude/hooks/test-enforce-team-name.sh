#!/bin/bash
# Test suite for .claude/hooks/enforce-team-name.sh
#
#   bash .claude/hooks/test-enforce-team-name.sh
#
# Exit 0: all tests pass. Exit 1: any failure.
#
# Covers:
#   - NAME MATCH (always): team_name must equal the declared name; mismatch DENY.
#   - PERMISSIVE default: Agent with no team_name passes (plain subagent).
#   - STRICT mode (via .claude/team.required file OR CLAUDE_TEAM_REQUIRED env):
#     missing team_name on Agent/TeamCreate -> DENY.
#   - CLAUDE_TEAM_NAME env overrides the file.
#   - No declaration -> permissive (cannot enforce).
#   - Non-gated tools pass through.
#
# The hook resolves files against $CLAUDE_PROJECT_DIR, so the harness PINS it to
# each fixture (NOT a bare cd) — otherwise an ambient CLAUDE_PROJECT_DIR in the
# caller's shell would make the hook read the real repo file, not the fixture.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/enforce-team-name.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

PASS=0
FAIL=0

# Run the hook with CLAUDE_PROJECT_DIR pinned to the fixture, so the team.name /
# team.required lookups are deterministic regardless of the caller's env.
run_hook() {  # fixture_dir, payload
  ( export CLAUDE_PROJECT_DIR="$1"; printf '%s' "$2" | bash "$HOOK" ) 2>/tmp/enforce-team-name-hook.err
}

get_decision() {
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$1" 2>/dev/null || echo "allow"
}

assert_allow() {  # label, fixture, payload
  local l="$1" c="$2" p="$3" o d
  o=$(run_hook "$c" "$p"); d=$(get_decision "$o")
  if [[ "$d" == "allow" ]]; then PASS=$((PASS+1)); printf '[allow OK ] %s\n' "$l"
  else FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected allow)\n' "$d" "$l"; echo "$o" | head -6 | sed 's/^/    | /'; fi
}

assert_deny() {  # label, fixture, payload
  local l="$1" c="$2" p="$3" o d
  o=$(run_hook "$c" "$p"); d=$(get_decision "$o")
  if [[ "$d" == "deny" ]]; then PASS=$((PASS+1)); printf '[deny  OK ] %s\n' "$l"
  else FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected deny)\n' "$d" "$l"; echo "$o" | head -6 | sed 's/^/    | /'; fi
}

# ── Fixtures ──────────────────────────────────────────────────────────────
FX=$(mktemp -d); trap "rm -rf $FX" EXIT
mkdir -p "$FX/permissive/.claude"; printf 'statbus\n' > "$FX/permissive/.claude/team.name"
mkdir -p "$FX/strict/.claude";     printf 'statbus\n' > "$FX/strict/.claude/team.name"; : > "$FX/strict/.claude/team.required"
mkdir -p "$FX/undeclared/.claude"  # no team.name

# Don't let the caller's shell leak into the file-based cases.
unset CLAUDE_TEAM_NAME CLAUDE_TEAM_REQUIRED

echo "── permissive (team.name=statbus, no team.required) ───────────────"
assert_allow "match: TeamCreate statbus"           "$FX/permissive" '{"tool_name":"TeamCreate","tool_input":{"team_name":"statbus"}}'
assert_deny  "mismatch: TeamCreate team (blocked)" "$FX/permissive" '{"tool_name":"TeamCreate","tool_input":{"team_name":"team"}}'
assert_deny  "mismatch: TeamCreate frogs"          "$FX/permissive" '{"tool_name":"TeamCreate","tool_input":{"team_name":"frogs"}}'
assert_allow "match: Agent statbus"                "$FX/permissive" '{"tool_name":"Agent","tool_input":{"team_name":"statbus","name":"architect"}}'
assert_deny  "mismatch: Agent team"                "$FX/permissive" '{"tool_name":"Agent","tool_input":{"team_name":"team","name":"x"}}'
assert_allow "no team_name: plain subagent passes" "$FX/permissive" '{"tool_name":"Agent","tool_input":{"name":"scout","description":"d","prompt":"p"}}'

echo "── strict via .claude/team.required marker file ───────────────────"
assert_allow "match: Agent statbus"                "$FX/strict" '{"tool_name":"Agent","tool_input":{"team_name":"statbus","name":"x"}}'
assert_deny  "mismatch: Agent team"                "$FX/strict" '{"tool_name":"Agent","tool_input":{"team_name":"team","name":"x"}}'
assert_deny  "no team_name: Agent DENIED"          "$FX/strict" '{"tool_name":"Agent","tool_input":{"name":"loose","description":"d","prompt":"p"}}'
assert_deny  "no team_name: TeamCreate DENIED"     "$FX/strict" '{"tool_name":"TeamCreate","tool_input":{}}'

echo "── strict via CLAUDE_TEAM_REQUIRED env ────────────────────────────"
export CLAUDE_TEAM_REQUIRED=1
assert_deny  "env strict: no team_name Agent DENIED" "$FX/permissive" '{"tool_name":"Agent","tool_input":{"name":"x","description":"d","prompt":"p"}}'
assert_allow "env strict: matching team_name OK"     "$FX/permissive" '{"tool_name":"Agent","tool_input":{"team_name":"statbus","name":"x"}}'
unset CLAUDE_TEAM_REQUIRED

echo "── CLAUDE_TEAM_NAME env overrides the file ────────────────────────"
export CLAUDE_TEAM_NAME=envteam
assert_allow "env name: create envteam (file=statbus)" "$FX/permissive" '{"tool_name":"TeamCreate","tool_input":{"team_name":"envteam"}}'
assert_deny  "env name: create statbus denied"         "$FX/permissive" '{"tool_name":"TeamCreate","tool_input":{"team_name":"statbus"}}'
unset CLAUDE_TEAM_NAME

echo "── no declaration → permissive (cannot enforce) ───────────────────"
assert_allow "undeclared: TeamCreate anything"     "$FX/undeclared" '{"tool_name":"TeamCreate","tool_input":{"team_name":"whatever"}}'
assert_allow "undeclared: no team_name Agent"      "$FX/undeclared" '{"tool_name":"Agent","tool_input":{"name":"x"}}'

echo "── non-gated tools pass through ───────────────────────────────────"
assert_allow "Bash"        "$FX/permissive" '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
assert_allow "TaskCreate"  "$FX/permissive" '{"tool_name":"TaskCreate","tool_input":{"subject":"s","description":"d"}}'
assert_allow "SendMessage" "$FX/permissive" '{"tool_name":"SendMessage","tool_input":{"to":"operator","summary":"s","message":"m"}}'

# ── Report ──────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
echo "────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
  echo "ALL GREEN: $PASS / $TOTAL tests passed"
  exit 0
else
  echo "FAILED: $FAIL / $TOTAL tests failed ($PASS passed)"
  exit 1
fi
