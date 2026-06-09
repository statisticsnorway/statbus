#!/bin/bash
# Test suite for .claude/hooks/enforce-team-name.sh
#
#   bash .claude/hooks/test-enforce-team-name.sh
#
# Exit 0: all tests pass. Exit 1: any failure.
#
# DEFAULT IS STRICT — teaming required unless explicitly opted out:
#   - NAME MATCH (always): team_name must equal the declared name; mismatch DENY.
#   - REQUIRED by default: a missing team_name on Agent/TeamCreate -> DENY.
#   - OPT-OUT (.claude/team.optional file OR CLAUDE_TEAM_OPTIONAL env): a missing
#     team_name -> ALLOW (plain subagent).
#   - CLAUDE_TEAM_NAME env overrides the declared-name file.
#   - No declaration -> permissive (cannot enforce a team that has no name).
#   - Non-gated tools pass through.
#
# The hook resolves files against $CLAUDE_PROJECT_DIR, so the harness PINS it to
# each fixture (not a bare cd) — otherwise an ambient CLAUDE_PROJECT_DIR would
# shadow the fixture's files.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/enforce-team-name.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

PASS=0
FAIL=0
run_hook() { ( export CLAUDE_PROJECT_DIR="$1"; printf '%s' "$2" | bash "$HOOK" ) 2>/tmp/enforce-team-name-hook.err; }
get_decision() { jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$1" 2>/dev/null || echo "allow"; }
assert_allow() { local l="$1" c="$2" p="$3" o d; o=$(run_hook "$c" "$p"); d=$(get_decision "$o");
  if [[ "$d" == "allow" ]]; then PASS=$((PASS+1)); printf '[allow OK ] %s\n' "$l"; else FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected allow)\n' "$d" "$l"; echo "$o" | head -6 | sed 's/^/    | /'; fi; }
assert_deny() { local l="$1" c="$2" p="$3" o d; o=$(run_hook "$c" "$p"); d=$(get_decision "$o");
  if [[ "$d" == "deny" ]]; then PASS=$((PASS+1)); printf '[deny  OK ] %s\n' "$l"; else FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected deny)\n' "$d" "$l"; echo "$o" | head -6 | sed 's/^/    | /'; fi; }

FX=$(mktemp -d); trap "rm -rf $FX" EXIT
mkdir -p "$FX/strict/.claude";  printf 'statbus\n' > "$FX/strict/.claude/team.name"             # default strict
mkdir -p "$FX/optout/.claude";  printf 'statbus\n' > "$FX/optout/.claude/team.name"; : > "$FX/optout/.claude/team.optional"
mkdir -p "$FX/undeclared/.claude"   # no team.name

unset CLAUDE_TEAM_NAME CLAUDE_TEAM_OPTIONAL

echo "── default strict (team.name=statbus, no team.optional) ───────────"
assert_allow "match: TeamCreate statbus"            "$FX/strict" '{"tool_name":"TeamCreate","tool_input":{"team_name":"statbus"}}'
assert_deny  "mismatch: TeamCreate team (blocked)"  "$FX/strict" '{"tool_name":"TeamCreate","tool_input":{"team_name":"team"}}'
assert_allow "match: Agent statbus"                 "$FX/strict" '{"tool_name":"Agent","tool_input":{"team_name":"statbus","name":"architect"}}'
assert_deny  "mismatch: Agent frogs"                "$FX/strict" '{"tool_name":"Agent","tool_input":{"team_name":"frogs","name":"x"}}'
assert_deny  "no team_name: Agent DENIED (default)" "$FX/strict" '{"tool_name":"Agent","tool_input":{"name":"loose","description":"d","prompt":"p"}}'
assert_deny  "no team_name: TeamCreate DENIED"      "$FX/strict" '{"tool_name":"TeamCreate","tool_input":{}}'

echo "── opt out via .claude/team.optional marker ───────────────────────"
assert_allow "no team_name: plain subagent passes"  "$FX/optout" '{"tool_name":"Agent","tool_input":{"name":"scout","description":"d","prompt":"p"}}'
assert_allow "match still allowed"                  "$FX/optout" '{"tool_name":"Agent","tool_input":{"team_name":"statbus","name":"x"}}'
assert_deny  "mismatch still denied"                "$FX/optout" '{"tool_name":"Agent","tool_input":{"team_name":"team","name":"x"}}'

echo "── opt out via CLAUDE_TEAM_OPTIONAL env ───────────────────────────"
export CLAUDE_TEAM_OPTIONAL=1
assert_allow "env optout: no team_name Agent passes" "$FX/strict" '{"tool_name":"Agent","tool_input":{"name":"x","description":"d","prompt":"p"}}'
assert_deny  "env optout: mismatch still denied"     "$FX/strict" '{"tool_name":"Agent","tool_input":{"team_name":"team","name":"x"}}'
unset CLAUDE_TEAM_OPTIONAL

echo "── CLAUDE_TEAM_NAME env overrides the file ────────────────────────"
export CLAUDE_TEAM_NAME=envteam
assert_allow "env name: create envteam (file=statbus)" "$FX/strict" '{"tool_name":"TeamCreate","tool_input":{"team_name":"envteam"}}'
assert_deny  "env name: create statbus denied"         "$FX/strict" '{"tool_name":"TeamCreate","tool_input":{"team_name":"statbus"}}'
unset CLAUDE_TEAM_NAME

echo "── no declaration → permissive (cannot enforce) ───────────────────"
assert_allow "undeclared: TeamCreate anything"      "$FX/undeclared" '{"tool_name":"TeamCreate","tool_input":{"team_name":"whatever"}}'
assert_allow "undeclared: no team_name Agent"       "$FX/undeclared" '{"tool_name":"Agent","tool_input":{"name":"x"}}'

echo "── non-gated tools pass through ───────────────────────────────────"
assert_allow "Bash"        "$FX/strict" '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
assert_allow "TaskCreate"  "$FX/strict" '{"tool_name":"TaskCreate","tool_input":{"subject":"s","description":"d"}}'
assert_allow "SendMessage" "$FX/strict" '{"tool_name":"SendMessage","tool_input":{"to":"operator","summary":"s","message":"m"}}'

TOTAL=$((PASS + FAIL))
echo "────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
  echo "ALL GREEN: $PASS / $TOTAL tests passed"
  exit 0
else
  echo "FAILED: $FAIL / $TOTAL tests failed ($PASS passed)"
  exit 1
fi
