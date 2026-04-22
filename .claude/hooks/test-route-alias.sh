#!/bin/bash
# Test suite for .claude/hooks/route-alias.sh
#
#   bash .claude/hooks/test-route-alias.sh
#
# Exit 0: all tests pass. Exit 1: any failure.
#
# Statbus aliases vs upstream:
#   main    → team-lead  (same as upstream)
#   counsel → team-lead  (new; replaces upstream's "hand" alias)
#
# Roster: team-lead, partner, paralegal, intern, lead-intern, test-intern
# (fixture — self-contained, no live team config needed)

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/route-alias.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

FIXTURE_DIR=$(mktemp -d)
trap "rm -rf $FIXTURE_DIR" EXIT

cat >"$FIXTURE_DIR/config.json" <<'JSON'
{
  "name": "test-fixture",
  "leadSessionId": "fixture-lead-session",
  "members": [
    {"agentId": "team-lead@test-fixture",   "name": "team-lead"},
    {"agentId": "partner@test-fixture",     "name": "partner"},
    {"agentId": "paralegal@test-fixture",   "name": "paralegal"},
    {"agentId": "intern@test-fixture",      "name": "intern"},
    {"agentId": "lead-intern@test-fixture", "name": "lead-intern"},
    {"agentId": "test-intern@test-fixture", "name": "test-intern"}
  ]
}
JSON
export CLAUDE_TEAM_CONFIG="$FIXTURE_DIR/config.json"

PASS=0
FAIL=0

run_hook() {
  printf '%s' "$1" | bash "$HOOK" 2>/tmp/route-alias-hook.err
}

get_decision() {
  jq -r '.hookSpecificOutput.permissionDecision // "no-op"' <<<"$1" 2>/dev/null || echo "no-op"
}

get_updated() {
  jq -r ".hookSpecificOutput.updatedInput$2 // \"none\"" <<<"$1" 2>/dev/null || echo "none"
}

assert_no_op() {
  local label="$1" payload="$2"
  local out dec
  out=$(run_hook "$payload")
  dec=$(get_decision "$out")
  if [[ "$dec" == "no-op" ]]; then
    PASS=$((PASS+1)); printf '[no-op OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected no-op)\n' "$dec" "$label"
    echo "$out" | head -10 | sed 's/^/    | /'
  fi
}

assert_allow_rewrite() {
  local label="$1" payload="$2" path="$3" expected="$4"
  local out dec actual
  out=$(run_hook "$payload")
  dec=$(get_decision "$out")
  actual=$(get_updated "$out" "$path")
  if [[ "$dec" == "allow" && "$actual" == "$expected" ]]; then
    PASS=$((PASS+1)); printf '[allow-rewrite OK ] %s  (%s="%s")\n' "$label" "$path" "$actual"
  else
    FAIL=$((FAIL+1)); printf '[%s/%s FAIL] %s  (expected allow, %s="%s")\n' "$dec" "$actual" "$label" "$path" "$expected"
    echo "$out" | head -10 | sed 's/^/    | /'
  fi
}

assert_deny() {
  local label="$1" payload="$2"
  local out dec
  out=$(run_hook "$payload")
  dec=$(get_decision "$out")
  if [[ "$dec" == "deny" ]]; then
    PASS=$((PASS+1)); printf '[deny  OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected deny)\n' "$dec" "$label"
    echo "$out" | head -10 | sed 's/^/    | /'
  fi
}

echo "── SendMessage: alias rewrites ─────────────────────────────────────"

assert_allow_rewrite "SendMessage to:main rewrites to team-lead" \
  '{"tool_name":"SendMessage","tool_input":{"to":"main","summary":"s","message":"m"}}' \
  '.to' 'team-lead'

assert_allow_rewrite "SendMessage to:counsel rewrites to team-lead" \
  '{"tool_name":"SendMessage","tool_input":{"to":"counsel","summary":"s","message":"m"}}' \
  '.to' 'team-lead'

echo "── SendMessage: valid roster members pass through ───────────────────"

assert_no_op "SendMessage to:team-lead is valid, no rewrite" \
  '{"tool_name":"SendMessage","tool_input":{"to":"team-lead","summary":"s","message":"m"}}'

assert_no_op "SendMessage to:partner is valid" \
  '{"tool_name":"SendMessage","tool_input":{"to":"partner","summary":"s","message":"m"}}'

assert_no_op "SendMessage to:paralegal is valid" \
  '{"tool_name":"SendMessage","tool_input":{"to":"paralegal","summary":"s","message":"m"}}'

assert_no_op "SendMessage to:intern is valid" \
  '{"tool_name":"SendMessage","tool_input":{"to":"intern","summary":"s","message":"m"}}'

assert_no_op "SendMessage to:lead-intern is valid" \
  '{"tool_name":"SendMessage","tool_input":{"to":"lead-intern","summary":"s","message":"m"}}'

assert_no_op "SendMessage to:test-intern is valid" \
  '{"tool_name":"SendMessage","tool_input":{"to":"test-intern","summary":"s","message":"m"}}'

echo "── SendMessage: broadcast and unknown ──────────────────────────────"

assert_no_op "SendMessage to:* broadcast is always allowed" \
  '{"tool_name":"SendMessage","tool_input":{"to":"*","summary":"s","message":"m"}}'

assert_deny "SendMessage to:nonexistent-xyzzy-42 is denied" \
  '{"tool_name":"SendMessage","tool_input":{"to":"nonexistent-xyzzy-42","summary":"s","message":"m"}}'

assert_deny "SendMessage to:hand is denied (not a statbus alias)" \
  '{"tool_name":"SendMessage","tool_input":{"to":"hand","summary":"s","message":"m"}}'

assert_deny "SendMessage to:tester is denied (not in fixture roster)" \
  '{"tool_name":"SendMessage","tool_input":{"to":"tester","summary":"s","message":"m"}}'

echo "── SendMessage: shutdown-protocol bypass ───────────────────────────"

assert_no_op "shutdown_request to:team-lead (valid) passes through unchanged" \
  '{"tool_name":"SendMessage","tool_input":{"to":"team-lead","message":{"type":"shutdown_request","reason":"r"}}}'

assert_deny "shutdown_request to:counsel is denied (no alias rewrite for shutdown traffic)" \
  '{"tool_name":"SendMessage","tool_input":{"to":"counsel","message":{"type":"shutdown_request","reason":"r"}}}'

assert_deny "shutdown_request to:phantom-xyz is denied" \
  '{"tool_name":"SendMessage","tool_input":{"to":"phantom-xyz","message":{"type":"shutdown_request","reason":"r"}}}'

# Other structured message types still get the normal alias rewrite
assert_allow_rewrite "plan_approval_request to:counsel still rewrites to team-lead" \
  '{"tool_name":"SendMessage","tool_input":{"to":"counsel","message":{"type":"plan_approval_request","request_id":"x","approve":true}}}' \
  '.to' 'team-lead'

assert_allow_rewrite "plan_approval_request to:main still rewrites to team-lead" \
  '{"tool_name":"SendMessage","tool_input":{"to":"main","message":{"type":"plan_approval_request","request_id":"x","approve":true}}}' \
  '.to' 'team-lead'

echo "── TaskCreate / TaskUpdate: owner rewrite and validation ────────────"

assert_allow_rewrite "TaskUpdate owner:main rewrites to team-lead" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"42","owner":"main"}}' \
  '.owner' 'team-lead'

assert_allow_rewrite "TaskUpdate owner:counsel rewrites to team-lead" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"42","owner":"counsel"}}' \
  '.owner' 'team-lead'

assert_no_op "TaskUpdate owner:team-lead is valid, no rewrite" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"42","owner":"team-lead"}}'

assert_no_op "TaskUpdate owner:partner is valid" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"42","owner":"partner"}}'

assert_no_op "TaskUpdate owner:intern is valid" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"42","owner":"intern"}}'

assert_deny "TaskUpdate owner:phantom-xyz is denied" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"42","owner":"phantom-xyz"}}'

assert_deny "TaskUpdate owner:hand is denied (not a statbus alias)" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"42","owner":"hand"}}'

assert_no_op "TaskUpdate with no owner field is a no-op (not every update touches owner)" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"42","status":"completed"}}'

assert_allow_rewrite "TaskCreate owner:main rewrites to team-lead" \
  '{"tool_name":"TaskCreate","tool_input":{"subject":"X","description":"Y","owner":"main"}}' \
  '.owner' 'team-lead'

assert_allow_rewrite "TaskCreate owner:counsel rewrites to team-lead" \
  '{"tool_name":"TaskCreate","tool_input":{"subject":"X","description":"Y","owner":"counsel"}}' \
  '.owner' 'team-lead'

assert_no_op "TaskCreate owner:lead-intern is valid" \
  '{"tool_name":"TaskCreate","tool_input":{"subject":"X","description":"Y","owner":"lead-intern"}}'

assert_deny "TaskCreate owner:typo-xyz is denied" \
  '{"tool_name":"TaskCreate","tool_input":{"subject":"X","description":"Y","owner":"typo-xyz"}}'

assert_no_op "TaskCreate with no owner field is a no-op" \
  '{"tool_name":"TaskCreate","tool_input":{"subject":"X","description":"Y"}}'

echo "── Other tools: pass through ────────────────────────────────────────"

assert_no_op "Read tool is not matched by this hook" \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'

assert_no_op "Bash tool is not matched by this hook" \
  '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'

assert_no_op "Agent tool is not matched by this hook" \
  '{"tool_name":"Agent","tool_input":{"description":"x","prompt":"y"}}'

# ── Report ──────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo "────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
  echo "ALL GREEN: $PASS / $TOTAL tests passed"
  exit 0
else
  echo "FAILED: $FAIL / $TOTAL tests failed ($PASS passed)"
  exit 1
fi
