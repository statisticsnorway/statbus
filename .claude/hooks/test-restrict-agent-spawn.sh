#!/bin/bash
# Test suite for .claude/hooks/restrict-agent-spawn.sh
#
#   bash .claude/hooks/test-restrict-agent-spawn.sh
#
# Exit 0: all tests pass. Exit 1: any failure.
#
# This suite tests the ACTUAL statbus hook against the ACTUAL statbus roster:
#   foreman  — roster name "team-lead" (agentType=="team-lead").
#   engineer, mechanic — opus/sonnet builders (may spawn? no — only foreman)
#   operator, tester   — sonnet legwork/test roles (read-only on git history)
#
# Rules under test:
#   Agent Rule 1  only the foreman may spawn agents
#   Agent Rule 2  foreman/unknown spawns must be background + bypassPermissions
#   Agent Rule 3  name-collision guard (can't spawn onto an existing roster name)
#   Bash  Rule 4  git commit/revert/cherry-pick/rebase/am/push → block operator+tester
#   Bash  Rule 5  ./sb release prerelease → foreman only (Tier 2, fail-closed on unknown)
#   Content strip HEREDOC bodies + git-commit-message bodies are NOT matched
#
# RETIRED (was Rule 4): the "only the tester may run ./dev.sh test" identity
# gate. Test-run serialization now lives in dev.sh (acquire_test_run_lock, an
# exclusive lock the runner takes itself). The hook no longer gates the test
# path at all — the cases below assert `./dev.sh test` is allowed for everyone.
#
# STATBUS-168 (hook-identity-rotation) — TWO DESIGNS, ONE SHIPPED:
# `leadSessionId` is REMOVED from both the hook and this fixture — a stored
# session id is exactly the stale-data vector that disarmed every guard
# across two production incidents. The FIRST replacement design (env marker
# CLAUDE_CODE_CHILD_SESSION: unset=root, set=child) was REFUTED by its own
# mandated probe (P1) before ship — the live foreman session's env had the
# marker SET too, indistinguishable from a teammate. Re-ruled same day to
# SPAWN-ARGV ANCESTRY (architect comment #7), validated live on both a root
# and a teammate session, from INSIDE a real hook invocation (PR1-PR3), with
# the in-process-subagent residual found EMPTY (PR4) and argv truncation
# ruled out (PR5, up to 287 chars observed).
#
# RESOLUTION ORDER this fixture exercises (comment #7; each step can only
# mis-DENY, never mis-GRANT):
#   1. ARGV IDENTITY (authoritative when a claude ancestor is found): walk
#      this process's own ancestry to the nearest `claude` entrypoint.
#      No --agent-name → ROOT → foreman. --agent-name X → caller IS X
#      (roster hit incl. team-lead→foreman normalization; non-roster →
#      unknown-child, decisively — does NOT fall through to step 2).
#   2. No claude ancestor found at all → TRANSCRIPT ROSTER-GREP fallback
#      (STATBUS-118 most-count match, unchanged mechanics) — covers a roster
#      teammate whose process happens to lack spawn argv.
#   3. Neither resolved anything → unknown-child (Tier 1 permissive; Tier 2
#      release DENIED).
#
# TEST SEAM: the hook's `_resolve_via_argv` function short-circuits to
# $STATBUS_HOOK_TEST_ARGV_RESULT when that env var is SET (even empty),
# skipping the real `ps` walk so this suite can stub all three resolution
# outcomes deterministically at the unit level, per the architect's own
# build spec ("simulates all three resolution outcomes by stubbing the
# walk"). The REAL walk (parsing --agent-name/--team-name out of genuine `ps
# -ww` argv) is validated separately by the PR1-PR5 LIVE acceptance probes
# against real root and teammate sessions (STATBUS-168 ticket comments) —
# NOT re-derived here. One exception this suite cannot stub: the walk's
# --team-name-mismatch bonus check (a cross-clone ancestor's team not
# matching this checkout) lives INSIDE the real ps-walk's own regex
# extraction, which the stub bypasses entirely; that specific behavior is
# verified by code review + the live probes, not asserted here — the
# cross-clone case below instead exercises the (equally load-bearing, and
# fully stub-testable) roster-LOOKUP crosstalk safety: an argv-identified
# name that isn't in THIS checkout's OWN roster is unknown-child here,
# regardless of which checkout it might belong to.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/restrict-agent-spawn.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

# Self-contained fixture: a synthetic team config with the real statbus roster
# shape (leadAgentId + per-member agentType), independent of any live team on
# the developer's machine.
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
  "leadAgentId": "team-lead@test-fixture",
  "members": [
    {"agentId": "team-lead@test-fixture", "name": "team-lead", "agentType": "team-lead"},
    {"agentId": "engineer@test-fixture",  "name": "engineer"},
    {"agentId": "mechanic@test-fixture",  "name": "mechanic"},
    {"agentId": "operator@test-fixture",  "name": "operator"},
    {"agentId": "tester@test-fixture",    "name": "tester"}
  ]
}
JSON

# Synthesize a transcript whose dominant agentName is $name — used ONLY by
# the dedicated Step-2 (transcript-fallback) test block below, which stubs
# the argv walk to "" (no claude ancestor found) so that fallback path is
# the one actually exercised.
mk_transcript() {
  local name="$1" file="$2"
  printf '{"type":"permission-mode","permissionMode":"acceptEdits","sessionId":"synthetic"}\n' > "$file"
  printf '{"parentUuid":null,"isSidechain":false,"teamName":"fixteam","agentName":"%s","type":"user"}\n' "$name" >> "$file"
}
mk_transcript "engineer"  "$TMPDIR/engineer.jsonl"
mk_transcript "mechanic"  "$TMPDIR/mechanic.jsonl"
mk_transcript "operator"  "$TMPDIR/operator.jsonl"
mk_transcript "tester"    "$TMPDIR/tester.jsonl"
mk_transcript "team-lead" "$TMPDIR/team-lead.jsonl"

PASS=0
FAIL=0

# ── Step-1 (argv) runners — the PRIMARY, realistic production path: every
# real spawned teammate process carries --agent-name in its own argv, so
# this is how identity actually resolves today, not the fallback. ──
# shellcheck disable=SC2329  # invoked indirectly, by name, via assert_* "$runner" "$payload"
run_hook_root() {   # STATBUS_HOOK_TEST_ARGV_RESULT=ROOT: claude ancestor, no --agent-name
  printf '%s' "$1" | env STATBUS_HOOK_TEST_ARGV_RESULT="ROOT" bash "$HOOK" 2>/tmp/restrict-hook.err
}
# shellcheck disable=SC2329  # called from run_hook_as_* wrappers, which are themselves invoked indirectly
_run_hook_as() {   # $1=argv agent-name, $2=payload
  printf '%s' "$2" | env STATBUS_HOOK_TEST_ARGV_RESULT="AGENT:$1" bash "$HOOK" 2>/tmp/restrict-hook.err
}
# shellcheck disable=SC2329
run_hook_as_engineer() { _run_hook_as "engineer" "$1"; }
# shellcheck disable=SC2329
run_hook_as_mechanic() { _run_hook_as "mechanic" "$1"; }
# shellcheck disable=SC2329
run_hook_as_operator() { _run_hook_as "operator" "$1"; }
# shellcheck disable=SC2329
run_hook_as_tester()   { _run_hook_as "tester" "$1"; }
# shellcheck disable=SC2329
run_hook_as_team_lead_argv() { _run_hook_as "team-lead" "$1"; }   # vocabulary normalization case
# shellcheck disable=SC2329
run_hook_argv_nonroster() { _run_hook_as "ffff-unknown-agent" "$1"; }   # named via argv, not in THIS roster

# ── Step-2/3 runners — argv walk finds NO claude ancestor at all, so the
# hook falls back to transcript roster-grep, and (if that also misses)
# lands on unknown-child. ──
# shellcheck disable=SC2329
run_hook_fallback() {   # $1=transcript_path baked into payload by the caller
  printf '%s' "$1" | env STATBUS_HOOK_TEST_ARGV_RESULT="" bash "$HOOK" 2>/tmp/restrict-hook.err
}
get_decision() {
  jq -r '.hookSpecificOutput.permissionDecision // "no-op"' <<<"$1" 2>/dev/null || echo "no-op"
}
get_system_message() {
  jq -r '.systemMessage // empty' <<<"$1" 2>/dev/null || echo ""
}

# Build a Bash-tool payload with an arbitrary (possibly multi-line) command.
bash_payload() { # sid transcript command
  jq -nc --arg sid "$1" --arg tp "$2" --arg cmd "$3" \
    '{session_id:$sid, transcript_path:$tp, tool_name:"Bash", tool_input:{command:$cmd}}'
}

assert_allow_or_no_op() {
  local label="$1" runner="$2" payload="$3" out dec
  out=$("$runner" "$payload"); dec=$(get_decision "$out")
  if [[ "$dec" == "allow" || "$dec" == "no-op" ]]; then
    PASS=$((PASS+1)); printf '[%-5s OK ] %s\n' "$dec" "$label"
  else
    FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s  (expected allow or no-op)\n' "$dec" "$label"
    echo "$out" | head -5 | sed 's/^/    | /'
  fi
}
assert_deny() {
  local label="$1" runner="$2" payload="$3" out dec
  out=$("$runner" "$payload"); dec=$(get_decision "$out")
  if [[ "$dec" == "deny" ]]; then
    PASS=$((PASS+1)); printf '[deny  OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s  (expected deny)\n' "$dec" "$label"
    echo "$out" | head -5 | sed 's/^/    | /'
  fi
}

echo "── Agent Rule 2: foreman spawn must be background + bypassPermissions ──"
# "foreman" here = argv ROOT (STATBUS-168: no session-id fixture needed —
# a claude ancestor with no --agent-name resolves to foreman, rotation-proof
# by construction — session_id below is arbitrary/rotated on purpose).

assert_deny "root(foreman) + foreground → DENY" run_hook_root \
  '{"session_id":"whatever-rotated-1","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":false,"mode":"bypassPermissions"}}'

assert_allow_or_no_op "root(foreman) + background + bypassPermissions → allow" run_hook_root \
  '{"session_id":"whatever-rotated-2","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

assert_deny "root(foreman) + background + default mode → DENY (subagent can't approve prompts)" run_hook_root \
  '{"session_id":"whatever-rotated-3","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"default"}}'

assert_deny "root(foreman) + background + missing mode → DENY (defaults to 'default')" run_hook_root \
  '{"session_id":"whatever-rotated-4","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true}}'

echo "── STATBUS-168: continuation-foreman across session-id rotation (argv ROOT) ──"
# The core rotation-proof claim: argv root-ness resolves to foreman
# regardless of session_id — no stored id, no fixture wiring, an
# arbitrary/rotated id works identically to any other.

assert_allow_or_no_op "argv ROOT, ARBITRARY/rotated session_id, no transcript match anywhere → foreman (bg+bypass allow)" run_hook_root \
  '{"session_id":"post-clear-brand-new-session-id-99999","transcript_path":"/tmp/fresh-post-clear-transcript-nonexistent.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

assert_deny "argv ROOT, ARBITRARY session_id, foreground spawn → DENY (still foreman, still Rule 2)" run_hook_root \
  '{"session_id":"another-rotated-id-12345","transcript_path":"/tmp/fresh-post-clear-transcript-nonexistent.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":false,"mode":"bypassPermissions"}}'

assert_allow_or_no_op "argv ROOT runs ./sb release prerelease with a rotated session_id → allow (Tier 2, still foreman)" run_hook_root \
  "$(bash_payload "totally-different-rotated-id" "/tmp/fresh-post-clear-transcript-nonexistent.jsonl" "./sb release prerelease")"

echo "── STATBUS-168: team-lead→foreman vocabulary normalization (via argv) ─"
# argv --agent-name team-lead (the routable roster name) must normalize to
# the role vocabulary "foreman" — same rules apply as argv ROOT (Rule 2
# bg/bypass; Rule 5 release allowed).

assert_deny "argv --agent-name team-lead, foreground spawn → DENY (still Rule 2)" run_hook_as_team_lead_argv \
  '{"session_id":"synthetic-team-lead","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":false,"mode":"bypassPermissions"}}'

assert_allow_or_no_op "argv --agent-name team-lead, bg+bypass → allow (normalized to foreman)" run_hook_as_team_lead_argv \
  '{"session_id":"synthetic-team-lead","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

assert_allow_or_no_op "argv --agent-name team-lead, ./sb release prerelease → allow (Tier 2, normalized foreman)" run_hook_as_team_lead_argv \
  "$(bash_payload "synthetic-team-lead" "/tmp/not-needed.jsonl" "./sb release prerelease")"

echo "── Agent Rule 1: only the foreman may spawn (argv-identified teammate) ──"

assert_deny "argv --agent-name engineer spawn (bg+bypass) → DENY (not foreman)" run_hook_as_engineer \
  '{"session_id":"synthetic-engineer","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

assert_deny "argv --agent-name mechanic spawn (bg+bypass) → DENY (not foreman)" run_hook_as_mechanic \
  '{"session_id":"synthetic-mechanic","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

assert_deny "argv --agent-name operator spawn (bg+bypass) → DENY (not foreman)" run_hook_as_operator \
  '{"session_id":"synthetic-operator","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

echo "── Agent Rule 3: name-collision guard ──────────────────────────────"

assert_deny "root(foreman) spawning name='engineer' (in roster) → DENY" run_hook_root \
  '{"session_id":"root-x","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"engineer","run_in_background":true,"mode":"bypassPermissions"}}'

assert_deny "root(foreman) spawning name='tester' (in roster) → DENY" run_hook_root \
  '{"session_id":"root-x","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"tester","run_in_background":true,"mode":"bypassPermissions"}}'

assert_allow_or_no_op "root(foreman) spawning name='auditor' (not in roster) → allow" run_hook_root \
  '{"session_id":"root-x","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"auditor","run_in_background":true,"mode":"bypassPermissions"}}'

assert_deny "argv operator spawning name='mechanic' (in roster) → DENY (collision before role check)" run_hook_as_operator \
  '{"session_id":"synthetic-operator","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"mechanic","run_in_background":true,"mode":"bypassPermissions"}}'

echo "── unknown-child: argv names a REAL spawned agent NOT in this roster ─"
# STATBUS-168 comment #7: an argv identity is AUTHORITATIVE even when the
# name isn't a roster member — it does NOT fall through to transcript-grep
# guessing something else. This is a genuinely spawned, genuinely
# unidentifiable (to THIS roster) child.

assert_deny "argv-named non-roster agent + foreground → DENY (blanket background rule, Tier 1)" run_hook_argv_nonroster \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":false,"mode":"bypassPermissions"}}'

assert_deny "argv-named non-roster agent + background + no bypassPermissions → DENY (blanket, Tier 1)" run_hook_argv_nonroster \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true}}'

assert_allow_or_no_op "argv-named non-roster agent + background + bypassPermissions → allow (Tier 1: can't apply role rule, permissive)" run_hook_argv_nonroster \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

echo "── STATBUS-168: Tier 1 (ordinary) vs Tier 2 (release) for unknown-child ─"
# The two-tier policy's own contrast case: the SAME unidentified caller is
# permissive on an ordinary op but denied on the authority-gated release op.

assert_allow_or_no_op "argv-named non-roster agent runs ./dev.sh test fast → allow (Tier 1, not gated at all — flock serializes)" run_hook_argv_nonroster \
  "$(bash_payload "ffff-unknown" "/tmp/definitely-not-a-file-12345.jsonl" "./dev.sh test fast")"

assert_deny "argv-named non-roster agent runs ./sb release prerelease → DENY (Tier 2, fail-closed)" run_hook_argv_nonroster \
  "$(bash_payload "ffff-unknown" "/tmp/definitely-not-a-file-12345.jsonl" "./sb release prerelease")"

echo "── STATBUS-168 Step 2: transcript roster-grep fallback (argv finds no claude ancestor) ─"
# The dedicated fallback case: STATBUS_HOOK_TEST_ARGV_RESULT="" simulates the
# walk finding NO claude ancestor at all (comment #7 step 2's precondition) —
# only THEN does transcript roster-grep get consulted, exactly as it did
# before the argv redesign, unchanged mechanics (STATBUS-118 most-count match).

assert_deny "argv finds nothing; transcript roster-hits 'engineer' → DENY spawn (identified, not foreman)" run_hook_fallback \
  "{\"session_id\":\"synthetic-engineer\",\"transcript_path\":\"$TMPDIR/engineer.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_allow_or_no_op "argv finds nothing; transcript roster-hits 'team-lead' → allow bg+bypass (normalized to foreman)" run_hook_fallback \
  "{\"session_id\":\"synthetic-team-lead\",\"transcript_path\":\"$TMPDIR/team-lead.jsonl\",\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"t\",\"run_in_background\":true,\"mode\":\"bypassPermissions\"}}"

assert_allow_or_no_op "argv finds nothing; transcript roster-hits 'team-lead' → allow ./sb release prerelease (fallback normalized foreman)" run_hook_fallback \
  "$(bash_payload "synthetic-team-lead" "$TMPDIR/team-lead.jsonl" "./sb release prerelease")"

echo "── STATBUS-168 Step 3: neither argv nor transcript resolve anything → unknown ─"

assert_deny "argv finds nothing; no transcript match either + foreground → DENY (blanket)" run_hook_fallback \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":false,"mode":"bypassPermissions"}}'

assert_allow_or_no_op "argv finds nothing; no transcript match; bg+bypass → allow (Tier 1 permissive)" run_hook_fallback \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}'

assert_deny "argv finds nothing; no transcript match; ./sb release prerelease → DENY (Tier 2)" run_hook_fallback \
  "$(bash_payload "ffff-unknown" "/tmp/definitely-not-a-file-12345.jsonl" "./sb release prerelease")"

echo "── Test path is NO LONGER gated (old Rule 4 retired) ───────────────"
# The flock in dev.sh serializes test runs; the hook must let ANY caller run
# ./dev.sh test — including a freshly started/unidentifiable agent. This is
# STATBUS-133 acceptance criterion #2 (no identity bootstrap on the test path).

assert_allow_or_no_op "root(foreman) runs ./dev.sh test fast → allow (flock serializes, not the hook)" run_hook_root \
  "$(bash_payload "root-x" "/tmp/not-needed.jsonl" "./dev.sh test fast 2>&1 | tee tmp/out.log")"

assert_allow_or_no_op "argv tester runs ./dev.sh test fast → allow" run_hook_as_tester \
  "$(bash_payload "synthetic-tester" "/tmp/not-needed.jsonl" "./dev.sh test fast")"

assert_allow_or_no_op "argv engineer runs ./dev.sh test all → allow" run_hook_as_engineer \
  "$(bash_payload "synthetic-engineer" "/tmp/not-needed.jsonl" "./dev.sh test all")"

assert_allow_or_no_op "argv operator runs ./dev.sh test 015_foo → allow" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" "./dev.sh test 015_foo")"

echo "── Bash Rule 4: git history ops → block operator + tester ──────────"

assert_deny "argv operator git push → DENY" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" "git push origin master")"

assert_deny "argv tester git commit → DENY" run_hook_as_tester \
  "$(bash_payload "synthetic-tester" "/tmp/not-needed.jsonl" "git commit -am wip")"

assert_deny "argv operator git rebase → DENY" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" "git rebase -i HEAD~2")"

assert_allow_or_no_op "argv engineer git commit → allow (builder role)" run_hook_as_engineer \
  "$(bash_payload "synthetic-engineer" "/tmp/not-needed.jsonl" "git commit -am 'fix'")"

assert_allow_or_no_op "argv mechanic git push → allow (builder role)" run_hook_as_mechanic \
  "$(bash_payload "synthetic-mechanic" "/tmp/not-needed.jsonl" "git push origin master")"

assert_allow_or_no_op "root(foreman) git push → allow" run_hook_root \
  "$(bash_payload "root-x" "/tmp/not-needed.jsonl" "git push origin master")"

echo "── Bash Rule 5: ./sb release prerelease → foreman only ─────────────"

assert_allow_or_no_op "root(foreman) ./sb release prerelease → allow" run_hook_root \
  "$(bash_payload "root-x" "/tmp/not-needed.jsonl" "./sb release prerelease")"

assert_deny "argv engineer ./sb release prerelease → DENY (not foreman)" run_hook_as_engineer \
  "$(bash_payload "synthetic-engineer" "/tmp/not-needed.jsonl" "./sb release prerelease")"

assert_deny "argv finds nothing, no transcript → ./sb release prerelease → DENY (can't confirm foreman)" run_hook_fallback \
  "$(bash_payload "ffff-unknown" "/tmp/definitely-not-a-file-12345.jsonl" "./sb release prerelease")"

echo "── STATBUS-168 (c): missing team config → LOUD, never silent ────────"
# A resolved-but-absent TEAM_CONFIG must never silently disarm the guards
# (the root incident this ticket exists for). Point CLAUDE_TEAM_NAME at a
# team that was never created; the hook still functions (argv ROOT→foreman,
# permissive Tier 1 for unknown) but every gated-path allow ALSO carries a
# top-level systemMessage naming the missing config.

run_hook_root_missing_config() {
  printf '%s' "$1" | env STATBUS_HOOK_TEST_ARGV_RESULT="ROOT" CLAUDE_TEAM_NAME="nonexistent-team-$$" bash "$HOOK" 2>/tmp/restrict-hook.err
}
run_hook_argv_nonroster_missing_config() {
  printf '%s' "$1" | env STATBUS_HOOK_TEST_ARGV_RESULT="AGENT:ffff-unknown-agent" CLAUDE_TEAM_NAME="nonexistent-team-$$" bash "$HOOK" 2>/tmp/restrict-hook.err
}

MC_OUT=$(run_hook_root_missing_config \
  "$(bash_payload "root-x" "/tmp/not-needed.jsonl" "git push origin master")")
MC_DEC=$(get_decision "$MC_OUT")
MC_SYS=$(get_system_message "$MC_OUT")
if [[ "$MC_DEC" == "allow" || "$MC_DEC" == "no-op" ]] && [[ "$MC_SYS" == *"team config NOT FOUND"* ]] && [[ "$MC_SYS" == *"role guards INACTIVE"* ]]; then
  PASS=$((PASS+1)); printf '[%-5s OK ] %s\n' "$MC_DEC" "missing config: root git push still allowed, systemMessage names the gap"
else
  FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s\n' "$MC_DEC" "missing config: root git push (expected allow + systemMessage naming the gap)"
  echo "$MC_OUT" | head -5 | sed 's/^/    | /'
fi

MC_OUT2=$(run_hook_argv_nonroster_missing_config \
  '{"session_id":"ffff-unknown","transcript_path":"/tmp/definitely-not-a-file-12345.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}')
MC_DEC2=$(get_decision "$MC_OUT2")
MC_SYS2=$(get_system_message "$MC_OUT2")
if [[ "$MC_DEC2" == "allow" || "$MC_DEC2" == "no-op" ]] && [[ -n "$MC_SYS2" ]]; then
  PASS=$((PASS+1)); printf '[%-5s OK ] %s\n' "$MC_DEC2" "missing config: unknown-child bg+bypass spawn still allowed, systemMessage present"
else
  FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s\n' "$MC_DEC2" "missing config: unknown-child bg+bypass spawn (expected allow + systemMessage)"
  echo "$MC_OUT2" | head -5 | sed 's/^/    | /'
fi

assert_deny "missing config: unknown-child ./sb release prerelease → still DENY (Tier 2 stays fail-closed)" run_hook_argv_nonroster_missing_config \
  "$(bash_payload "ffff-unknown" "/tmp/definitely-not-a-file-12345.jsonl" "./sb release prerelease")"

echo "── STATBUS-168: cross-clone two-checkout fixture (roster-lookup crosstalk safety) ─"
# Two checkouts on one machine, each with its own live team (STATBUS-122
# carry-over, comment #1). CLAUDE_TEAM_NAME is UNSET for this block so
# resolve_team_name falls through to each checkout's OWN .claude/team.name —
# proving cwd-scoped resolution, not a shared env var. The SAME argv-stubbed
# identity ("engineer-a") is asserted against BOTH checkouts' rosters: clone
# A recognizes it (own roster), clone B does not (different roster) —
# proving no crosstalk at the roster-LOOKUP layer. (The walk's own
# --team-name-mismatch bonus check is a separate, non-stubbable code path —
# see the header note.)

CLONE_A="$TMPDIR/clone-a"; CLONE_B="$TMPDIR/clone-b"
mkdir -p "$CLONE_A/.claude" "$CLONE_B/.claude"
echo "fixteam-a" > "$CLONE_A/.claude/team.name"
echo "fixteam-b" > "$CLONE_B/.claude/team.name"
mkdir -p "$TMPDIR/teams/fixteam-a" "$TMPDIR/teams/fixteam-b"
cat > "$TMPDIR/teams/fixteam-a/config.json" <<'JSON'
{
  "name": "fixteam-a",
  "leadAgentId": "team-lead@fixteam-a",
  "members": [
    {"agentId": "team-lead@fixteam-a", "name": "team-lead", "agentType": "team-lead"},
    {"agentId": "engineer-a@fixteam-a", "name": "engineer-a"}
  ]
}
JSON
cat > "$TMPDIR/teams/fixteam-b/config.json" <<'JSON'
{
  "name": "fixteam-b",
  "leadAgentId": "team-lead@fixteam-b",
  "members": [
    {"agentId": "team-lead@fixteam-b", "name": "team-lead", "agentType": "team-lead"},
    {"agentId": "engineer-b@fixteam-b", "name": "engineer-b"}
  ]
}
JSON

run_hook_argv_in_dir() { # dir agent-name payload
  (cd "$1" && printf '%s' "$3" | env -u CLAUDE_TEAM_NAME STATBUS_HOOK_TEST_ARGV_RESULT="AGENT:$2" bash "$HOOK" 2>/tmp/restrict-hook.err)
}

# "engineer-a" resolved from clone A's cwd → clone A's OWN team.name →
# fixteam-a's roster → identified as engineer-a → DENY on Agent spawn
# (identified, not foreman).
OUT_A=$(run_hook_argv_in_dir "$CLONE_A" "engineer-a" \
  '{"session_id":"x","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}')
DEC_A=$(get_decision "$OUT_A")
if [[ "$DEC_A" == "deny" ]]; then
  PASS=$((PASS+1)); printf '[deny  OK ] %s\n' "clone A resolves argv 'engineer-a' via its own team.name → DENY (identified, not foreman)"
else
  FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s\n' "$DEC_A" "clone A resolves argv 'engineer-a' (expected deny)"
  echo "$OUT_A" | head -5 | sed 's/^/    | /'
fi

# THE SAME argv-identified name "engineer-a" (who does NOT exist in team B's
# roster), invoked from clone B's cwd → clone B's OWN team.name resolves
# fixteam-b, whose roster has no "engineer-a" → unknown-child (bg+bypass
# still satisfied → Tier 1 permissive allow). Proves clone B's roster LOOKUP
# never cross-resolves clone A's roster.
OUT_B=$(run_hook_argv_in_dir "$CLONE_B" "engineer-a" \
  '{"session_id":"x","transcript_path":"/tmp/not-needed.jsonl","tool_name":"Agent","tool_input":{"name":"t","run_in_background":true,"mode":"bypassPermissions"}}')
DEC_B=$(get_decision "$OUT_B")
if [[ "$DEC_B" == "allow" || "$DEC_B" == "no-op" ]]; then
  PASS=$((PASS+1)); printf '[%-5s OK ] %s\n' "$DEC_B" "clone B does NOT resolve clone A's 'engineer-a' (no roster-lookup crosstalk) → unknown-child, Tier 1 allow"
else
  FAIL=$((FAIL+1)); printf '[%-5s FAIL] %s\n' "$DEC_B" "clone B cross-resolved clone A's roster — crosstalk bug (expected allow/no-op, unknown-child)"
  echo "$OUT_B" | head -5 | sed 's/^/    | /'
fi

echo "── Content false-positive prevention: HEREDOC bodies (STATBUS-133 #3) ──"
# A command that WRITES a file whose CONTENT mentions a gated command must not
# be blocked. Only commands EXECUTED (outside heredoc bodies) are gated.

# (a) operator authors a runbook whose body contains `git push` → allow.
#     Without the heredoc strip, Rule 4 would match `git push` and DENY.
assert_allow_or_no_op "operator authors file; heredoc body has 'git push' → allow" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" \
     $'cat > tmp/runbook.md <<\'EOF\'\nTo deploy: git push origin master\nEOF')"

# (b) operator authors a deploy script whose body runs `./sb release prerelease`
#     → allow. Without the strip, Rule 5 would match and DENY.
assert_allow_or_no_op "operator authors file; heredoc body has './sb release prerelease' → allow" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" \
     $'cat > tmp/deploy.sh <<\'EOF\'\n./sb release prerelease\nEOF')"

# (c) the originally reported symptom: authoring a launcher whose text mentions
#     `./dev.sh test` must not be blocked (doubly safe now — Rule 4 retired AND
#     the body is stripped).
assert_allow_or_no_op "engineer authors launcher; heredoc body has './dev.sh test' → allow" run_hook_as_engineer \
  "$(bash_payload "synthetic-engineer" "/tmp/not-needed.jsonl" \
     $'cat > tmp/launch.sh <<\'EOF\'\n#!/bin/bash\n./dev.sh test fast\nEOF')"

# (d) <<-EOF (tab-indented terminator) body is also stripped.
assert_allow_or_no_op "operator authors file; <<-EOF tabbed body has 'git push' → allow" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" \
     $'cat <<-EOF > tmp/x\n\tgit push origin master\n\tEOF')"

echo "── Content strip must NOT over-strip real executed commands ─────────"

# (e) CONTROL: a real executed `git push` (no heredoc) by operator → still DENY.
assert_deny "operator bare 'git push' (executed, not content) → still DENY" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" "git push origin master")"

# (f) CONTROL: a real executed release by a non-foreman → still DENY.
assert_deny "engineer bare './sb release prerelease' (executed) → still DENY" run_hook_as_engineer \
  "$(bash_payload "synthetic-engineer" "/tmp/not-needed.jsonl" "./sb release prerelease")"

# (g) A real command BEFORE a heredoc opener is still seen (opener line kept).
assert_deny "operator 'git push && cat <<EOF ...' → DENY (push is on the opener line, executed)" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" \
     $'git push origin master && cat > tmp/y <<EOF\nnothing gated here\nEOF')"

# (h) RESUMPTION: a gated command AFTER the heredoc TERMINATOR must still deny —
#     matching resumes once the body closes.
assert_deny "operator: heredoc, then 'git push' on a line AFTER the terminator → DENY" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" \
     $'cat > tmp/x <<EOF\nharmless body line\nEOF\ngit push origin master')"

# (i) HERE-STRING guard: `<<<` is not a heredoc opener, so it must NOT swallow a
#     following real command. Without the (^|[^<]) guard, line 2's git push would
#     be misread as heredoc body and dropped → the block would silently weaken.
assert_deny "operator: here-string on line 1, real 'git push' on line 2 → DENY (<<< not an opener)" run_hook_as_operator \
  "$(bash_payload "synthetic-operator" "/tmp/not-needed.jsonl" \
     $'grep foo <<< "$marker"\ngit push origin master')"

echo "── Content false-positive prevention: git commit message bodies ────"
# git commit -m "..." bodies are stripped, so a command documented inside a
# commit message must not match a rule. Engineer may commit (Rule 4 allows),
# and the release string in the body must not trip Rule 5.

assert_allow_or_no_op "engineer git commit -m body mentions './sb release prerelease' → allow" run_hook_as_engineer \
  "$(bash_payload "synthetic-engineer" "/tmp/not-needed.jsonl" \
     "git commit -m \"docs: how to run ./sb release prerelease\"")"

assert_allow_or_no_op "engineer git commit -F file → allow (-F path stripped)" run_hook_as_engineer \
  "$(bash_payload "synthetic-engineer" "/tmp/not-needed.jsonl" "git commit -F tmp/commit-msg.txt")"

echo "── non-Agent, non-Bash tools: pass through ─────────────────────────"

assert_allow_or_no_op "Read tool → no-op" run_hook_root \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'

assert_allow_or_no_op "SendMessage tool → no-op" run_hook_root \
  '{"tool_name":"SendMessage","tool_input":{"to":"x","message":"y"}}'

assert_allow_or_no_op "TaskUpdate tool → no-op" run_hook_root \
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
