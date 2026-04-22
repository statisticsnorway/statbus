#!/bin/bash
# Test suite for .claude/hooks/require-git-c.sh
#
#   bash .claude/hooks/test-require-git-c.sh
#
# The hook is DEACTIVATED by default (HOOK_ENABLED_REQUIRE_GIT_C=0).
# Export the env var here so all test invocations exercise the live logic.
export HOOK_ENABLED_REQUIRE_GIT_C=1

# CLAUDE_PROJECT_DIR is set to a valid git repo (the statbus project root)
# so the `git worktree list` call inside the hook works correctly.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/require-git-c.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

# Point CLAUDE_PROJECT_DIR at the project root (two levels up from .claude/hooks/).
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

PASS=0
FAIL=0

run_hook() {
  printf '%s' "$1" | bash "$HOOK" 2>/tmp/require-git-c.err
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
    echo "$out" | head -5 | sed 's/^/    | /'
  fi
}

assert_allow_or_no_op() {
  local label="$1" payload="$2"
  local out dec
  out=$(run_hook "$payload")
  dec=$(get_decision "$out")
  if [[ "$dec" == "allow" || "$dec" == "no-op" ]]; then
    PASS=$((PASS+1)); printf '[%-5s OK ] %s\n' "$dec" "$label"
  else
    FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected allow or no-op)\n' "$dec" "$label"
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
    FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected deny)\n' "$dec" "$label"
    echo "$out" | head -5 | sed 's/^/    | /'
  fi
}

assert_no_op_disabled() {
  local label="$1" payload="$2"
  local out dec
  out=$(printf '%s' "$payload" | HOOK_ENABLED_REQUIRE_GIT_C=0 bash "$HOOK" 2>/dev/null)
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

assert_no_op_disabled "bare git passes through when hook disabled" \
  "$(payload_for 'git status')"

echo "── DENY: bare git without -C ────────────────────────────────────────"

assert_deny "git status  (no -C)" \
  "$(payload_for 'git status')"
assert_deny "git add ." \
  "$(payload_for 'git add .')"
assert_deny "git commit -m msg" \
  "$(payload_for 'git commit -m msg')"
assert_deny "git diff HEAD" \
  "$(payload_for 'git diff HEAD')"
assert_deny "git log --oneline" \
  "$(payload_for 'git log --oneline')"

echo "── PASS: git -C <path> commands ────────────────────────────────────"

assert_allow_or_no_op "git -C /repo status" \
  "$(payload_for "git -C $REPO_ROOT status")"
assert_allow_or_no_op "git -C /repo add ." \
  "$(payload_for "git -C $REPO_ROOT add .")"
assert_allow_or_no_op "git -C /repo commit -m msg" \
  "$(payload_for "git -C $REPO_ROOT commit -m msg")"
assert_allow_or_no_op "git -C /repo log --oneline" \
  "$(payload_for "git -C $REPO_ROOT log --oneline")"
assert_allow_or_no_op "git -C /repo diff HEAD" \
  "$(payload_for "git -C $REPO_ROOT diff HEAD")"

echo "── PASS: excluded git commands (no repo needed) ─────────────────────"

assert_allow_or_no_op "git help" \
  "$(payload_for 'git help commit')"
assert_allow_or_no_op "git --version" \
  "$(payload_for 'git --version')"
assert_allow_or_no_op "git version" \
  "$(payload_for 'git version')"
assert_allow_or_no_op "git config --global user.name" \
  "$(payload_for 'git config --global user.name')"

echo "── PASS: non-git Bash and other tools ──────────────────────────────"

assert_no_op "echo hello  (not git)" \
  "$(payload_for 'echo hello')"
assert_no_op "ls -la" \
  "$(payload_for 'ls -la')"
assert_no_op "./sb psql" \
  "$(payload_for './sb psql')"
assert_no_op "Read tool" \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'
assert_no_op "SendMessage tool" \
  '{"tool_name":"SendMessage","tool_input":{"to":"team-lead","summary":"s","message":"m"}}'

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
