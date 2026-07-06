#!/bin/bash
# Test suite for .claude/hooks/restrict-agent-spawn.sh
#
#   bash .claude/hooks/test-restrict-agent-spawn.sh
#
# Exit 0: all tests pass. Exit 1: any failure.
#
# This suite tests the ACTUAL statbus hook against the ACTUAL statbus roster:
#   foreman  — identified via session_id == leadSessionId
#   engineer, mechanic — opus/sonnet builders (may spawn? no — only foreman)
#   operator, tester   — sonnet legwork/test roles (read-only on git history)
#
# Rules under test:
#   Agent Rule 1  only the foreman may spawn agents
#   Agent Rule 2  foreman/unknown spawns must be background + bypassPermissions
#   Agent Rule 3  name-collision guard (can't spawn onto an existing roster name)
#   Bash  Rule 4  git commit/revert/cherry-pick/rebase/am/push → block operator+tester
#   Bash  Rule 5  ./sb release prerelease → foreman only
#   Content strip HEREDOC bodies + git-commit-message bodies are NOT matched
#
# RETIRED (was Rule 4): the "only the tester may run ./dev.sh test" identity
# gate. Test-run serialization now lives in dev.sh (acquire_test_run_lock, an
# exclusive lock the runner takes itself). The hook no longer gates the test
# path at all — the cases below assert `./dev.sh test` is allowed for everyone.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/restrict-agent-spawn.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

# Self-contained fixture: a synthetic team config with the real statbus roster,
# independent of any live team on the developer's machine.
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# The hook resolves its team config from
#   $CLAUDE_CONFIG_DIR/teams/<resolve_team_name>/config.json
# Pin both so it reads this fixture regardless of ambient config / team.name.
export CLAUDE_CONFIG_DIR="$TMPDIR"
export CLAUDE_TEAM_NAME="fixteam"
TEAM_CONFIG="$TMPDIR/teams/fixteam/config.json"
mkdir -p "$(dirname "$TEAM_CONFIG")"
cat >"$TEAM_CONFIG" <<'JSON'
{
  "name": "test-fixture",
  "leadSessionId": "fixture-lead-session",
  "members": [
    {"agentId": "foreman@test-fixture",  "name": "foreman"},
    {"agentId": "engineer@test-fixture", "name": "engineer"},
    {"agentId": "mechanic@test-fixture", "name": "mechanic"},
    {"agentId": "operator@test-fixture", "name": "operator"},
    {"agentId": "tester@test-fixture",   "name": "tester"}
  ]
}
JSON
LEAD_SID="fixture-lead-session"

# Synthesize a transcript whose dominant agentName is $name (how the hook
# resolves a non-foreman caller's identity).
mk_transcript() {
  local name="$1" file="$2"
  printf '{"type":"permission-mode","permissionMode":"acceptEdits","sessionId":"synthetic"}\n' > "$file"
  printf '{"parentUuid":null,"isSidechain":false,"teamName":"fixteam","agentName":"%s","type":"user"}\n' "$name" >> "$file"
}
mk_transcript "engineer" "$TMPDIR/engineer.jsonl"
mk_transcript "mechanic" "$TMPDIR/mechanic.jsonl"
mk_transcript "operator" "$TMPDIR/operator.jsonl"
mk_transcript "tester"   "$TMPDIR/tester.jsonl"

PASS=0
FAIL=0

run_hook() {
  printf '%s' "$1" | bash "$HOOK" 2>/tmp/restrict-hook.err
}
get_decision() {
  jq -r '.hookSpecificOutput.permissionDecision // "no-op"' <<<"$1" 2>/dev/null || echo "no-op"
}

# Build a Bash-tool payload with an arbitrary (possibly multi-line) command.
bash_payload() { # sid transcript command
  jq -nc --arg sid "$1" --arg tp "$2" --arg cmd "$3" \
    '{session_id:$sid, transcript_path:$tp, tool_name:"Bash", tool_input:{command:$cmd}}'
}

assert_allow_or_no_op() {
  local label="$1" payload="$2" out dec
  out=$(run_hook "$payload"); dec=$(get_decision "$out")
  if [[ "$dec" == "allow" || "$dec" == "no-op" ]]; then
    PASS=$((PASS+1)); printf '[%-5s OK ] %s\n' "$dec" "$label"
  else
    FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s  (expected allow or no-op)\n' "$dec" "$label"
    echo "$out" | head -5 | sed 's/^/    | /'
  fi
}
assert_deny() {
  local label="$1" payload="$2" out dec
  out=$(run_hook "$payload"); dec=$(get_decision "$out")
  if [[ "$dec" == "deny" ]]; then
    PASS=$((PASS+1)); printf '[deny  OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s  (expected deny)\n' "$dec" "$label"
    echo "$out" | head -5 | sed 's/^/    | /'
  fi
}

echo "── Agent Rule 2: foreman spawn must be background + bypassPermissions ──"

assert_deny "foreman + foreground → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":false,\"mode\":\"bypassPermissions\"}}"

assert_allow_or_no_op "foreman + background + bypassPermissions → allow" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "foreman + background + default mode → DENY (subagent can't approve prompts)" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"default\"}}"

assert_deny "foreman + background + missing mode → DENY (defaults to 'default')" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true}}"

echo "── Agent Rule 1: only the foreman may spawn ────────────────────────"

assert_deny "engineer spawn (bg+bypass) → DENY (not foreman)" \
  "{\"session_id\":\"synthetic-engineer\",\"transcript_path\":\"$TMPDIR/engineer.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "mechanic spawn (bg+bypass) → DENY (not foreman)" \
  "{\"session_id\":\"synthetic-mechanic\",\"transcript_path\":\"$TMPDIR/mechanic.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "operator spawn (bg+bypass) → DENY (not foreman)" \
  "{\"session_id\":\"synthetic-operator\",\"transcript_path\":\"$TMPDIR/operator.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

echo "── Agent Rule 3: name-collision guard ──────────────────────────────"

assert_deny "foreman spawning name='engineer' (in roster) → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"engineer\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "foreman spawning name='tester' (in roster) → DENY" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"tester\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_allow_or_no_op "foreman spawning name='auditor' (not in roster) → allow" \
  "{\"session_id\":\"$LEAD_SID\",\"transcript_path\":\"/tmp/not-needed.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"auditor\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_deny "operator spawning name='mechanic' (in roster) → DENY (collision before role check)" \
  "{\"session_id\":\"synthetic-operator\",\"transcript_path\":\"$TMPDIR/operator.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"mechanic\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

echo "── unknown caller (blanket Agent rules still enforced) ──────────────"

assert_deny "unknown caller + foreground → DENY (blanket background rule)" \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":false,"mode":"bypassPermissions"}}'

assert_deny "unknown caller + background + no bypassPermissions → DENY (blanket)" \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true}}'

assert_allow_or_no_op "unknown caller + background + bypassPermissions → allow (can't apply role rule)" \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

echo "── Test path is NO LONGER gated (old Rule 4 retired) ───────────────"
# The flock in dev.sh serializes test runs; the hook must let ANY caller run
# ./dev.sh test — including a freshly started/unidentifiable agent. This is
# STATBUS-133 acceptance criterion #2 (no identity bootstrap on the test path).

assert_allow_or_no_op "foreman runs ./dev.sh test fast → allow (flock serializes, not the hook)" \
  "$(bash_payload "$LEAD_SID" "/tmp/not-needed.jsonl" "./dev.sh test fast 2>&1 | tee tmp/out.log")"

assert_allow_or_no_op "tester runs ./dev.sh test fast → allow" \
  "$(bash_payload "synthetic-tester" "$TMPDIR/tester.jsonl" "./dev.sh test fast")"

assert_allow_or_no_op "engineer runs ./dev.sh test all → allow" \
  "$(bash_payload "synthetic-engineer" "$TMPDIR/engineer.jsonl" "./dev.sh test all")"

assert_allow_or_no_op "operator runs ./dev.sh test 015_foo → allow" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" "./dev.sh test 015_foo")"

assert_allow_or_no_op "unknown caller runs ./dev.sh test fast → allow (fresh agent, no bootstrap)" \
  "$(bash_payload "ffff-unknown" "/tmp/definitely-not-a-file-12345.jsonl" "./dev.sh test fast")"

echo "── Bash Rule 4: git history ops → block operator + tester ──────────"

assert_deny "operator git push → DENY" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" "git push origin master")"

assert_deny "tester git commit → DENY" \
  "$(bash_payload "synthetic-tester" "$TMPDIR/tester.jsonl" "git commit -am wip")"

assert_deny "operator git rebase → DENY" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" "git rebase -i HEAD~2")"

assert_allow_or_no_op "engineer git commit → allow (builder role)" \
  "$(bash_payload "synthetic-engineer" "$TMPDIR/engineer.jsonl" "git commit -am 'fix'")"

assert_allow_or_no_op "mechanic git push → allow (builder role)" \
  "$(bash_payload "synthetic-mechanic" "$TMPDIR/mechanic.jsonl" "git push origin master")"

assert_allow_or_no_op "foreman git push → allow" \
  "$(bash_payload "$LEAD_SID" "/tmp/not-needed.jsonl" "git push origin master")"

echo "── Bash Rule 5: ./sb release prerelease → foreman only ─────────────"

assert_allow_or_no_op "foreman ./sb release prerelease → allow" \
  "$(bash_payload "$LEAD_SID" "/tmp/not-needed.jsonl" "./sb release prerelease")"

assert_deny "engineer ./sb release prerelease → DENY (not foreman)" \
  "$(bash_payload "synthetic-engineer" "$TMPDIR/engineer.jsonl" "./sb release prerelease")"

assert_deny "unknown caller ./sb release prerelease → DENY (can't confirm foreman)" \
  "$(bash_payload "ffff-unknown" "/tmp/definitely-not-a-file-12345.jsonl" "./sb release prerelease")"

echo "── Content false-positive prevention: HEREDOC bodies (STATBUS-133 #3) ──"
# A command that WRITES a file whose CONTENT mentions a gated command must not
# be blocked. Only commands EXECUTED (outside heredoc bodies) are gated.

# (a) operator authors a runbook whose body contains `git push` → allow.
#     Without the heredoc strip, Rule 4 would match `git push` and DENY.
assert_allow_or_no_op "operator authors file; heredoc body has 'git push' → allow" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" \
     $'cat > tmp/runbook.md <<\'EOF\'\nTo deploy: git push origin master\nEOF')"

# (b) operator authors a deploy script whose body runs `./sb release prerelease`
#     → allow. Without the strip, Rule 5 would match and DENY.
assert_allow_or_no_op "operator authors file; heredoc body has './sb release prerelease' → allow" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" \
     $'cat > tmp/deploy.sh <<\'EOF\'\n./sb release prerelease\nEOF')"

# (c) the originally reported symptom: authoring a launcher whose text mentions
#     `./dev.sh test` must not be blocked (doubly safe now — Rule 4 retired AND
#     the body is stripped).
assert_allow_or_no_op "engineer authors launcher; heredoc body has './dev.sh test' → allow" \
  "$(bash_payload "synthetic-engineer" "$TMPDIR/engineer.jsonl" \
     $'cat > tmp/launch.sh <<\'EOF\'\n#!/bin/bash\n./dev.sh test fast\nEOF')"

# (d) <<-EOF (tab-indented terminator) body is also stripped.
assert_allow_or_no_op "operator authors file; <<-EOF tabbed body has 'git push' → allow" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" \
     $'cat <<-EOF > tmp/x\n\tgit push origin master\n\tEOF')"

echo "── Content strip must NOT over-strip real executed commands ─────────"

# (e) CONTROL: a real executed `git push` (no heredoc) by operator → still DENY.
assert_deny "operator bare 'git push' (executed, not content) → still DENY" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" "git push origin master")"

# (f) CONTROL: a real executed release by a non-foreman → still DENY.
assert_deny "engineer bare './sb release prerelease' (executed) → still DENY" \
  "$(bash_payload "synthetic-engineer" "$TMPDIR/engineer.jsonl" "./sb release prerelease")"

# (g) A real command BEFORE a heredoc opener is still seen (opener line kept).
assert_deny "operator 'git push && cat <<EOF ...' → DENY (push is on the opener line, executed)" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" \
     $'git push origin master && cat > tmp/y <<EOF\nnothing gated here\nEOF')"

# (h) RESUMPTION: a gated command AFTER the heredoc TERMINATOR must still deny —
#     matching resumes once the body closes.
assert_deny "operator: heredoc, then 'git push' on a line AFTER the terminator → DENY" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" \
     $'cat > tmp/x <<EOF\nharmless body line\nEOF\ngit push origin master')"

# (i) HERE-STRING guard: `<<<` is not a heredoc opener, so it must NOT swallow a
#     following real command. Without the (^|[^<]) guard, line 2's git push would
#     be misread as heredoc body and dropped → the block would silently weaken.
assert_deny "operator: here-string on line 1, real 'git push' on line 2 → DENY (<<< not an opener)" \
  "$(bash_payload "synthetic-operator" "$TMPDIR/operator.jsonl" \
     $'grep foo <<< "$marker"\ngit push origin master')"

echo "── Content false-positive prevention: git commit message bodies ────"
# git commit -m "..." bodies are stripped, so a command documented inside a
# commit message must not match a rule. Engineer may commit (Rule 4 allows),
# and the release string in the body must not trip Rule 5.

assert_allow_or_no_op "engineer git commit -m body mentions './sb release prerelease' → allow" \
  "$(bash_payload "synthetic-engineer" "$TMPDIR/engineer.jsonl" \
     "git commit -m \"docs: how to run ./sb release prerelease\"")"

assert_allow_or_no_op "engineer git commit -F file → allow (-F path stripped)" \
  "$(bash_payload "synthetic-engineer" "$TMPDIR/engineer.jsonl" "git commit -F tmp/commit-msg.txt")"

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
