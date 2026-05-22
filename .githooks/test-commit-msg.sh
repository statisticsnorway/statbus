#!/bin/bash
# Test suite for .githooks/commit-msg
#
#   bash .githooks/test-commit-msg.sh
#
# Exit 0: all tests pass. Exit 1: any failure.
#
# The hook receives a file path containing the commit message as $1.
# Tests write synthetic messages to temp files and pipe them to the hook.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/commit-msg"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

run_hook() {
  local msg="$1"
  local f="$TMPDIR/msg.txt"
  printf '%s' "$msg" > "$f"
  bash "$HOOK" "$f" 2>/tmp/commit-msg.err
}

assert_pass() {
  local label="$1" msg="$2"
  local exit_code=0
  run_hook "$msg" || exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    PASS=$((PASS+1)); printf '[pass  OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[FAIL     ] %s  (expected exit 0, got %d)\n' "$label" "$exit_code"
    cat /tmp/commit-msg.err | head -5 | sed 's/^/    | /'
  fi
}

assert_reject() {
  local label="$1" msg="$2"
  local exit_code=0
  run_hook "$msg" || exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    PASS=$((PASS+1)); printf '[reject OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[FAIL     ] %s  (expected exit 1, got 0)\n' "$label"
  fi
}

echo "── REJECT: bare hash-digit references (task IDs, issue shorthand, etc) ──"

assert_reject "task-style hash with digits" \
  "fix: health check URL

Closes Task #94."

assert_reject "github-style bare issue ref" \
  "fix: workaround for claude-code#25135 silent drop bug"

assert_reject "fix prefix + hash-digit shorthand" \
  "fix #25135: SendMessage silent drop"

assert_reject "see issue + hash-digit" \
  "see issue #100 for context"

assert_reject "closes + hash-digit" \
  "closes #42"

assert_reject "two hash-digits in one line" \
  "fix: resolved issue #1 and issue #2"

assert_reject "hash-digit inside parentheses" \
  "fix: tighten validation (refs #68 — observed on jo)"

echo "── PASS: URL-embedded references (URLs may contain # legitimately) ──"

assert_pass "github issue URL" \
  "fix: workaround for https://github.com/statisticsnorway/statbus/issues/100"

assert_pass "github PR URL with fragment" \
  "see https://github.com/anthropics/claude-code/pull/200#issuecomment-456 for the upstream discussion"

assert_pass "URL in parens" \
  "fix the auth flow (https://github.com/foo/bar/issues/12)"

echo "── PASS: clean commit messages ─────────────────────────────────────"

assert_pass "simple one-liner" \
  "fix: health check uses correct PostgREST URL"

assert_pass "multi-line with body" \
  "feat(install): detect crashed upgrade state

Previously the install command would silently skip a crashed upgrade.
Now it detects the stale flag and reconciles before re-dispatching."

assert_pass "commit with co-author trailer" \
  "fix(worker): eliminate timing race in collect_changes

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"

assert_pass "message mentioning 'task' as a noun (not a number)" \
  "chore: improve task routing documentation"

assert_pass "message with 'tasks' but no number" \
  "docs: clarify how tasks are assigned to teammates"

echo "── PASS: comment lines are ignored ──────────────────────────────────"

assert_pass "git comment lines with # are not flagged" \
  "fix: normal message

# This is a git comment line — should be ignored
# task #94 here in a comment — should NOT trigger rejection
Real body line."

echo "── PASS: empty / whitespace-only messages ───────────────────────────"

assert_pass "empty message" ""

assert_pass "whitespace only" "   "

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
