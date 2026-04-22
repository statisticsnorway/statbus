#!/bin/bash
# Test suite for .claude/hooks/remind-plan-update.sh

set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/remind-plan-update.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

PASS=0
FAIL=0

assert_has_context() {
  local label="$1" payload="$2"
  local out ctx
  out=$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
  if [[ -n "$ctx" ]]; then
    PASS=$((PASS+1)); printf '[remind OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[FAIL] %s  (expected additionalContext reminder)\n' "$label"
  fi
}

assert_no_op() {
  local label="$1" payload="$2"
  local out
  out=$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)
  if [[ "$out" == "{}" ]]; then
    PASS=$((PASS+1)); printf '[no-op  OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[FAIL] %s  (expected {}, got %s)\n' "$label" "${out:0:60}"
  fi
}

assert_has_context "TaskUpdate status=completed fires reminder" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"5","status":"completed"}}'

assert_no_op "TaskUpdate status=in_progress" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"5","status":"in_progress"}}'

assert_no_op "TaskUpdate status=pending" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"5","status":"pending"}}'

assert_no_op "TaskUpdate status=deleted" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"5","status":"deleted"}}'

assert_no_op "TaskUpdate owner change (no status)" \
  '{"tool_name":"TaskUpdate","tool_input":{"taskId":"5","owner":"paralegal"}}'

assert_no_op "TaskCreate (different tool)" \
  '{"tool_name":"TaskCreate","tool_input":{"subject":"x","status":"completed"}}'

assert_no_op "SendMessage" \
  '{"tool_name":"SendMessage","tool_input":{"to":"team-lead","status":"completed"}}'

TOTAL=$((PASS + FAIL))
echo "────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
  echo "ALL GREEN: $PASS / $TOTAL tests passed"
  exit 0
else
  echo "FAILED: $FAIL / $TOTAL tests failed ($PASS passed)"
  exit 1
fi
