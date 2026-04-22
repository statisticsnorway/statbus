#!/bin/bash
# Test suite for .claude/hooks/restrict-agent-spawn.sh
#
#   bash .claude/hooks/test-restrict-agent-spawn.sh
#
# Exit 0: all tests pass. Exit 1: any failure.
#
# Statbus role mapping vs upstream:
#   team-lead   — identified via session_id == leadSessionId (unchanged)
#   interns     — names matching (^|-)intern$ (intern, lead-intern, test-intern, ...)
#                 (upstream: *-scout pattern)
#   lane actors — partner, paralegal, any non-intern non-team-lead
#                 (upstream: non-scout subagents)

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/restrict-agent-spawn.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

# Test fixture: synthetic team config with a known roster so tests are
# self-contained and independent of any live team on the developer's machine.
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat >"$TMPDIR/config.json" <<'JSON'
{
  "name": "test-fixture",
  "leadSessionId": "fixture-lead-session",
  "members": [
    {"agentId": "team-lead@test-fixture",  "name": "team-lead"},
    {"agentId": "partner@test-fixture",    "name": "partner"},
    {"agentId": "paralegal@test-fixture",  "name": "paralegal"},
    {"agentId": "intern@test-fixture",     "name": "intern"},
    {"agentId": "lead-intern@test-fixture","name": "lead-intern"},
    {"agentId": "tester@test-fixture",     "name": "tester"}
  ]
}
JSON
export CLAUDE_TEAM_CONFIG="$TMPDIR/config.json"
TEAM_CONFIG="$CLAUDE_TEAM_CONFIG"
LEAD_SID="fixture-lead-session"

# Synthesize a transcript with a given agentName (same format as upstream).
mk_transcript() {
  local name="$1" file="$2"
  printf '{"type":"permission-mode","permissionMode":"acceptEdits","sessionId":"synthetic"}\n' > "$file"
  printf '{"parentUuid":null,"isSidechain":false,"teamName":"team","agentName":"%s","type":"user"}\n' "$name" >> "$file"
}

# Transcripts for the statbus roles
mk_transcript "intern"       "$TMPDIR/intern.jsonl"
mk_transcript "lead-intern"  "$TMPDIR/lead-intern.jsonl"
mk_transcript "test-intern"  "$TMPDIR/test-intern.jsonl"
mk_transcript "partner"      "$TMPDIR/partner.jsonl"
mk_transcript "paralegal"    "$TMPDIR/paralegal.jsonl"
mk_transcript "tester"       "$TMPDIR/tester.jsonl"

PASS=0
FAIL=0

run_hook() {
  printf '%s' "$1" | bash "$HOOK" 2>/tmp/restrict-hook.err
}

get_decision() {
  jq -r '.hookSpecificOutput.permissionDecision // "no-op"' <<<"$1" 2>/dev/null || echo "no-op"
}

assert_allow_or_no_op() {
  local label="$1" payload="$2"
  local out dec
  out=$(run_hook "$payload")
  dec=$(get_decision "$out")
  if [[ "$dec" == "allow" || "$dec" == "no-op" ]]; then
    PASS=$((PASS+1)); printf '[%-5s OK ] %s\n' "$dec" "$label"
  else
    FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s  (expected allow or no-op)\n' "$dec" "$label"
    echo "$out" | head -5 | sed 's/^/    | /'
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
    FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s  (expected deny)\n' "$dec" "$label"
    echo "$out" | head -5 | sed 's/^/    | /'
  fi
}

echo "── team-lead paths ─────────────────────────────────────────────────"

assert_deny "team-lead + foreground → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":false,\"mode\":\"bypassPermissions\"}}"

assert_allow_or_no_op "team-lead + background + bypassPermissions → allow" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "team-lead + background + default mode → DENY (subagent can't approve prompts)" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"default\"}}"

assert_deny "team-lead + background + missing mode → DENY (defaults to 'default')" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true}}"

echo "── intern paths (replaces upstream scout paths) ────────────────────"

assert_allow_or_no_op "intern + background + bypassPermissions → allow" \
  "{\"session_id\":\"synthetic-intern\",\"transcript_path\":\"$TMPDIR/intern.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "intern + foreground → DENY" \
  "{\"session_id\":\"synthetic-intern\",\"transcript_path\":\"$TMPDIR/intern.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":false,\"mode\":\"bypassPermissions\"}}"

assert_deny "intern + background + default mode → DENY" \
  "{\"session_id\":\"synthetic-intern\",\"transcript_path\":\"$TMPDIR/intern.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"default\"}}"

assert_allow_or_no_op "lead-intern + background + bypassPermissions → allow (is_intern matches)" \
  "{\"session_id\":\"synthetic-lead-intern\",\"transcript_path\":\"$TMPDIR/lead-intern.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "lead-intern + foreground → DENY" \
  "{\"session_id\":\"synthetic-lead-intern\",\"transcript_path\":\"$TMPDIR/lead-intern.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":false,\"mode\":\"bypassPermissions\"}}"

assert_allow_or_no_op "test-intern + background + bypassPermissions → allow (is_intern matches)" \
  "{\"session_id\":\"synthetic-test-intern\",\"transcript_path\":\"$TMPDIR/test-intern.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

echo "── lane actor paths (partner, paralegal, tester) ───────────────────"

assert_deny "partner + background → DENY (lane actor)" \
  "{\"session_id\":\"synthetic-partner\",\"transcript_path\":\"$TMPDIR/partner.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true}}"

assert_deny "partner + foreground → DENY (lane actor)" \
  "{\"session_id\":\"synthetic-partner\",\"transcript_path\":\"$TMPDIR/partner.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":false}}"

assert_deny "paralegal + background → DENY (lane actor)" \
  "{\"session_id\":\"synthetic-paralegal\",\"transcript_path\":\"$TMPDIR/paralegal.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true}}"

assert_deny "tester + background → DENY (lane actor — name does not match intern pattern)" \
  "{\"session_id\":\"synthetic-tester\",\"transcript_path\":\"$TMPDIR/tester.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true}}"

echo "── name-collision guard (Rule 3) ───────────────────────────────────"

assert_deny "team-lead spawning name='partner' (in roster) → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"partner\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "team-lead spawning name='intern' (in roster) → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"intern\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "team-lead spawning name='lead-intern' (in roster) → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"lead-intern\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_allow_or_no_op "team-lead spawning name='auditor' (not in roster) → allow" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"auditor\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "intern spawning name='paralegal' (in roster) → DENY (collision before role check)" \
  "{\"session_id\":\"synthetic-intern\",\"transcript_path\":\"$TMPDIR/intern.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"paralegal\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

echo "── unknown caller (blanket rules still enforced) ───────────────────"

assert_deny "unknown caller + Agent + foreground → DENY (blanket background rule)" \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":false,"mode":"bypassPermissions"}}'

assert_deny "unknown caller + Agent + background + no bypassPermissions → DENY (blanket)" \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true}}'

assert_allow_or_no_op "unknown caller + Agent + background + bypassPermissions → allow (can't apply lane-actor rule)" \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

echo "── Tier-1 Bash gating (Rule 4) ─────────────────────────────────────"

assert_deny "team-lead runs ./dev.sh test fast → DENY (Tier-1, not test-intern)" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./dev.sh test fast 2>&1 | tee tmp/out.log\"}}"

assert_deny "intern runs ./dev.sh test fast → DENY (Tier-1, not test-intern)" \
  "{\"session_id\":\"synthetic-intern\",\"transcript_path\":\"$TMPDIR/intern.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./dev.sh test fast\"}}"

assert_deny "partner runs ./dev.sh test all → DENY (Tier-1, lane actor)" \
  "{\"session_id\":\"synthetic-partner\",\"transcript_path\":\"$TMPDIR/partner.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./dev.sh test all\"}}"

assert_allow_or_no_op "test-intern runs ./dev.sh test fast → allow (authorized Tier-1 runner)" \
  "{\"session_id\":\"synthetic-test-intern\",\"transcript_path\":\"$TMPDIR/test-intern.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./dev.sh test fast\"}}"

assert_deny "team-lead runs ./sb types generate → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./sb types generate\"}}"

assert_allow_or_no_op "test-intern runs ./sb types generate → allow" \
  "{\"session_id\":\"synthetic-test-intern\",\"transcript_path\":\"$TMPDIR/test-intern.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./sb types generate\"}}"

assert_deny "team-lead runs ./dev.sh generate-db-documentation → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./dev.sh generate-db-documentation\"}}"

assert_allow_or_no_op "test-intern runs ./dev.sh generate-db-documentation → allow" \
  "{\"session_id\":\"synthetic-test-intern\",\"transcript_path\":\"$TMPDIR/test-intern.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./dev.sh generate-db-documentation\"}}"

assert_deny "team-lead runs ./sb release prerelease → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./sb release prerelease\"}}"

assert_allow_or_no_op "test-intern runs ./sb release prerelease → allow" \
  "{\"session_id\":\"synthetic-test-intern\",\"transcript_path\":\"$TMPDIR/test-intern.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"./sb release prerelease\"}}"

assert_allow_or_no_op "team-lead runs a regular Bash command → allow (not Tier-1)" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hello\"}}"

assert_deny "unknown caller runs ./dev.sh test fast → DENY (Tier-1, can't confirm test-intern)" \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Bash","tool_input":{"command":"./dev.sh test fast"}}'

echo "── non-Agent, non-Bash tools: pass through ─────────────────────────"

assert_allow_or_no_op "Read tool → no-op" \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'

assert_allow_or_no_op "SendMessage tool → no-op" \
  '{"tool_name":"SendMessage","tool_input":{"to":"x","message":"y"}}'

assert_allow_or_no_op "TaskUpdate tool → no-op" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

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
