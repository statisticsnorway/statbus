#!/bin/bash
# Test suite for .claude/hooks/require-task-slug.sh
#
#   bash .claude/hooks/test-require-task-slug.sh
#
# Hook is ACTIVE by default (HOOK_ENABLED_REQUIRE_TASK_SLUG=1).
# The disabled-guard test overrides inline with HOOK_ENABLED_REQUIRE_TASK_SLUG=0.
#
# A synthetic task directory is created in /tmp for uniqueness tests.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/require-task-slug.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

# Synthetic task dir with two pre-existing tasks (both with slugs)
TASK_DIR=$(mktemp -d)
cat > "$TASK_DIR/1.json" <<'JSON'
{"id":"1","subject":"existing-task: something already registered"}
JSON
cat > "$TASK_DIR/2.json" <<'JSON'
{"id":"2","subject":"another-slug: another existing task"}
JSON
export CLAUDE_TASK_DIR="$TASK_DIR"

PASS=0
FAIL=0

run_hook() {
  printf '%s' "$1" | bash "$HOOK" 2>/tmp/require-task-slug.err
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
    echo "$out" | head -3 | sed 's/^/    | /'
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
    echo "$out" | head -3 | sed 's/^/    | /'
  fi
}

assert_no_op_disabled() {
  local label="$1" payload="$2"
  local out dec
  out=$(printf '%s' "$payload" | HOOK_ENABLED_REQUIRE_TASK_SLUG=0 bash "$HOOK" 2>/dev/null)
  dec=$(get_decision "$out")
  if [[ "$dec" == "no-op" ]]; then
    PASS=$((PASS+1)); printf '[no-op OK ] %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '[%s FAIL] %s  (expected no-op when disabled)\n' "$dec" "$label"
  fi
}

tc() { jq -nc --arg subj "$1" '{"tool_name":"TaskCreate","tool_input":{"subject":$subj,"description":"d"}}'; }
tu() { jq -nc --arg subj "$1" --arg id "$2" '{"tool_name":"TaskUpdate","tool_input":{"taskId":$id,"subject":$subj}}'; }
tu_no_subj() { jq -nc --arg id "$1" '{"tool_name":"TaskUpdate","tool_input":{"taskId":$id,"status":"completed"}}'; }

echo "── DISABLED guard ───────────────────────────────────────────────────"

assert_no_op_disabled "TaskCreate without slug passes when hook disabled" \
  "$(tc 'No slug here at all')"

echo "── DENY: TaskCreate missing slug ────────────────────────────────────"

assert_deny "no slug prefix at all" \
  "$(tc 'Fix the login bug')"
assert_deny "old bracket format rejected" \
  "$(tc '[fix-bug] Fix the login bug')"
assert_deny "colon but no space after" \
  "$(tc 'fix-bug:description without space')"
assert_deny "colon+space but empty body" \
  "$(tc 'fix-bug: ')"

echo "── DENY: TaskCreate malformed slug ──────────────────────────────────"

assert_deny "slug too short (2 chars)" \
  "$(tc 'ab: Some task')"
assert_deny "slug starts with digit" \
  "$(tc '1fix: Cannot start with digit')"
assert_deny "slug starts with hyphen" \
  "$(tc '-bad: Leading hyphen')"
assert_deny "slug uppercase first char" \
  "$(tc 'Fix: Uppercase first char')"
assert_deny "slug uppercase mid-word" \
  "$(tc 'fix-Bug: Mixed case')"
assert_deny "slug contains dot" \
  "$(tc 'fix.bug: Dot not allowed')"
assert_deny "slug contains underscore" \
  "$(tc 'fix_bug: Underscore not allowed')"
assert_deny "slug too long (32 chars)" \
  "$(tc 'abcdefghijklmnopqrstuvwxyz123456: Too long')"

echo "── DENY: TaskCreate duplicate slug ──────────────────────────────────"

assert_deny "duplicate slug 'existing-task'" \
  "$(tc 'existing-task: new task with same slug')"
assert_deny "duplicate slug 'another-slug'" \
  "$(tc 'another-slug: another duplicate')"

echo "── PASS: TaskCreate valid slug ───────────────────────────────────────"

assert_no_op "minimal 3-char slug" \
  "$(tc 'abc: Short but valid')"
assert_no_op "normal kebab slug" \
  "$(tc 'fix-login-bug: Fix the login bug')"
assert_no_op "slug with digits" \
  "$(tc 'rc52-upgrade: Upgrade to rc.52')"
assert_no_op "single word slug" \
  "$(tc 'maintenance: Daily maintenance task')"
assert_no_op "31-char slug (max)" \
  "$(tc 'abcdefghijklmnopqrstuvwxyz12345: Max length slug')"
assert_no_op "realistic task subject" \
  "$(tc 'require-slug-hook: enforce slug prefix on TaskCreate')"
assert_no_op "slug ends with digit" \
  "$(tc 'rune-rc52: Upgrade rune to rc.52')"

echo "── PASS: TaskUpdate without subject change ───────────────────────────"

assert_no_op "TaskUpdate status only (no subject)" \
  "$(tu_no_subj '1')"
assert_no_op "TaskUpdate owner only (no subject)" \
  "$(jq -nc '{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","owner":"paralegal"}}')"

echo "── PASS: TaskUpdate subject change — valid new slug ─────────────────"

assert_no_op "TaskUpdate with valid new slug" \
  "$(tu 'updated-slug: Updated task subject' '1')"

echo "── PASS: TaskUpdate keeping own slug (id excluded from uniqueness) ───"

assert_no_op "TaskUpdate keeping 'existing-task' slug on task id=1" \
  "$(tu 'existing-task: Revised title same slug' '1')"

echo "── DENY: TaskUpdate stealing slug from another task ─────────────────"

assert_deny "TaskUpdate taking 'another-slug' from task id=2 while editing id=1" \
  "$(tu 'another-slug: Stealing another task slug' '1')"

echo "── PASS: non-task tools pass through ────────────────────────────────"

assert_no_op "Bash tool not matched" \
  '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
assert_no_op "SendMessage tool not matched" \
  '{"tool_name":"SendMessage","tool_input":{"to":"team-lead","summary":"s","message":"m"}}'
assert_no_op "Read tool not matched" \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'

# ── cleanup ──────────────────────────────────────────────────────────────
rm -rf "$TASK_DIR"

# ── report ───────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
echo "────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
  echo "ALL GREEN: $PASS / $TOTAL tests passed"
  exit 0
else
  echo "FAILED: $FAIL / $TOTAL tests failed ($PASS passed)"
  exit 1
fi
