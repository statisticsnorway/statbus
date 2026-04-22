#!/bin/bash
# Test suite for .claude/hooks/ban-force-add.sh
#
#   bash .claude/hooks/test-ban-force-add.sh
#
# The hook is DEACTIVATED by default (HOOK_ENABLED_BAN_FORCE_ADD=0).
# Export the env var here so all test invocations exercise the live logic.
export HOOK_ENABLED_BAN_FORCE_ADD=1

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/ban-force-add.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

PASS=0
FAIL=0

run_hook() {
  printf '%s' "$1" | bash "$HOOK" 2>/tmp/hook.err
}

get_decision() {
  jq -r '.hookSpecificOutput.permissionDecision // "no-op"' <<<"$1" 2>/dev/null || echo "no-op"
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
  fi
}

assert_no_op_disabled() {
  # Verify hook is truly a no-op when HOOK_ENABLED_BAN_FORCE_ADD=0.
  local label="$1" payload="$2"
  local out dec
  out=$(printf '%s' "$payload" | HOOK_ENABLED_BAN_FORCE_ADD=0 bash "$HOOK" 2>/dev/null)
  dec=$(get_decision "$out")
  if [[ "$dec" == "no-op" ]]; then
    PASS=$((PASS+1)); printf '[no-op OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected no-op when disabled)\n' "$dec" "$label"
  fi
}

payload_for() {
  jq -nc --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

echo "── DISABLED guard ───────────────────────────────────────────────────"

assert_no_op_disabled "git add -f passes through when hook disabled" \
  "$(payload_for 'git add -f foo.txt')"

echo "── DENY: core force-add patterns ───────────────────────────────────"

assert_deny "git add -f foo.txt" \
  "$(payload_for 'git add -f foo.txt')"
assert_deny "git add --force foo.txt" \
  "$(payload_for 'git add --force foo.txt')"
assert_deny "git add -f ." \
  "$(payload_for 'git add -f .')"
assert_deny "git -C /path add -f file" \
  "$(payload_for 'git -C /some/path add -f file.sh')"
assert_deny "git -C /path add --force file" \
  "$(payload_for 'git -C /some/path add --force file.sh')"
assert_deny "git add foo.txt -f  (flag after filename)" \
  "$(payload_for 'git add foo.txt -f')"
assert_deny "git add foo --force" \
  "$(payload_for 'git add foo --force')"
assert_deny "git add -f -v foo.txt  (combined flags)" \
  "$(payload_for 'git add -f -v foo.txt')"
assert_deny "git add --verbose --force foo" \
  "$(payload_for 'git add --verbose --force foo')"

echo "── DENY: chained commands ───────────────────────────────────────────"

assert_deny "chained: safe then force-add" \
  "$(payload_for 'echo hello && git add -f foo')"
assert_deny "chained: force-add then safe" \
  "$(payload_for 'git add -f foo && echo done')"
assert_deny "chained with ;: force-add in middle" \
  "$(payload_for 'ls; git add -f foo; date')"
assert_deny "chained with |: piped then force-add" \
  "$(payload_for 'echo x | tee y.txt; git add -f y.txt')"

echo "── PASS: normal git add and other git commands ──────────────────────"

assert_no_op "git add foo.txt" \
  "$(payload_for 'git add foo.txt')"
assert_no_op "git add ." \
  "$(payload_for 'git add .')"
assert_no_op "git -C /path add ." \
  "$(payload_for 'git -C /some/path add .')"
assert_no_op "git add -p  (interactive, no force)" \
  "$(payload_for 'git add -p')"
assert_no_op "git commit -m 'foo'" \
  "$(payload_for 'git commit -m x')"
assert_no_op "git status" \
  "$(payload_for 'git status')"

echo "── PASS: out-of-scope destructive flags ─────────────────────────────"

assert_no_op "git push --force  (out of scope)" \
  "$(payload_for 'git push --force origin master')"
assert_no_op "git reset --hard  (out of scope)" \
  "$(payload_for 'git reset --hard HEAD~1')"
assert_no_op "git clean -f  (clean -f is not add -f)" \
  "$(payload_for 'git clean -f')"

echo "── PASS: non-git Bash and other tools ──────────────────────────────"

assert_no_op "echo hello" \
  "$(payload_for 'echo hello')"
assert_no_op "ls -la" \
  "$(payload_for 'ls -la')"
assert_no_op "cp foo bar" \
  "$(payload_for 'cp foo bar')"
assert_no_op "Read tool is not matched" \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'
assert_no_op "SendMessage is not matched" \
  '{"tool_name":"SendMessage","tool_input":{"to":"team-lead","summary":"s","message":"m"}}'

echo "── PASS: tricky strings that look close but are not force-add ───────"

assert_no_op "echo 'git add -f'  (quoted)" \
  "$(payload_for "echo 'git add -f'")"
assert_no_op "rm -rf  (not git)" \
  "$(payload_for 'rm -rf /tmp/junk')"

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
