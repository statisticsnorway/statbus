#!/bin/bash
# Test suite for .claude/hooks/require-bash-background.sh (statbus variant)
#
#   bash .claude/hooks/test-require-bash-background.sh
#
# Exit 0: all tests pass. Exit 1: any failure.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/require-bash-background.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

PASS=0
FAIL=0

run_hook() { printf '%s' "$1" | bash "$HOOK" 2>/tmp/bash-bg.err; }
get_decision() { jq -r '.hookSpecificOutput.permissionDecision // "no-op"' <<<"$1" 2>/dev/null || echo "no-op"; }

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

payload_fg()      { jq -nc --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'; }
payload_bg()      { jq -nc --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd,"run_in_background":true}}'; }
payload_timeout() { jq -nc --arg cmd "$1" --argjson t "$2" '{"tool_name":"Bash","tool_input":{"command":$cmd,"timeout":$t}}'; }

# ── DENY: statbus-specific long patterns, foreground ──

assert_deny "./dev.sh test fast foreground" \
  "$(payload_fg './dev.sh test fast 2>&1 | tee tmp/out.log')"

assert_deny "./dev.sh test single foreground" \
  "$(payload_fg './dev.sh test 346_migration_rebuilds_derived_tables')"

assert_deny "./dev.sh create-db foreground" \
  "$(payload_fg './dev.sh create-db')"

assert_deny "./dev.sh recreate-database foreground" \
  "$(payload_fg './dev.sh recreate-database')"

assert_deny "./dev.sh delete-db foreground" \
  "$(payload_fg './dev.sh delete-db')"

assert_deny "./dev.sh update-snapshot foreground" \
  "$(payload_fg './dev.sh update-snapshot')"

assert_deny "./dev.sh generate-doc-db foreground" \
  "$(payload_fg './dev.sh generate-doc-db')"

assert_deny "./sb install foreground" \
  "$(payload_fg './sb install')"

assert_deny "./sb upgrade apply foreground" \
  "$(payload_fg './sb upgrade apply v2026.04.0-rc.48')"

assert_deny "./sb release prerelease foreground" \
  "$(payload_fg './sb release prerelease')"

assert_deny "./sb db restore foreground" \
  "$(payload_fg './sb db restore dbdumps/statbus_local.dump')"

assert_deny "./sb db dump foreground" \
  "$(payload_fg './sb db dump')"

assert_deny "pnpm run build foreground" \
  "$(payload_fg 'cd app && pnpm run build')"

assert_deny "pnpm run test foreground" \
  "$(payload_fg 'cd app && pnpm run test')"

assert_deny "pnpm install foreground" \
  "$(payload_fg 'cd app && pnpm install')"

assert_deny "pnpm ci foreground" \
  "$(payload_fg 'cd app && pnpm ci')"

assert_deny "docker compose logs -f foreground" \
  "$(payload_fg 'docker compose logs -f worker')"

assert_deny "docker compose logs app -f foreground" \
  "$(payload_fg 'docker compose logs app -f')"

assert_deny "docker compose up (no -d) foreground" \
  "$(payload_fg 'docker compose up')"

assert_deny "docker compose up with services (no -d) foreground" \
  "$(payload_fg 'docker compose up db worker')"

# ── DENY: inherited patterns, foreground ──

assert_deny "tail -f foreground" \
  "$(payload_fg 'tail -f tmp/test.log')"

assert_deny "watch command foreground" \
  "$(payload_fg 'watch -n 2 docker compose ps')"

assert_deny "nice prefix foreground" \
  "$(payload_fg 'nice -n 10 ./dev.sh test fast')"

# ── DENY: explicit timeout > 30s, foreground ──

assert_deny "timeout 60000ms foreground" \
  "$(payload_timeout 'echo anything' 60000)"

assert_deny "timeout 31000ms foreground (just over threshold)" \
  "$(payload_timeout 'echo anything' 31000)"

# ── PASS: same commands with run_in_background: true ──

assert_no_op "./dev.sh test fast backgrounded" \
  "$(payload_bg './dev.sh test fast 2>&1 | tee tmp/out.log')"

assert_no_op "./sb install backgrounded" \
  "$(payload_bg './sb install')"

assert_no_op "pnpm run build backgrounded" \
  "$(payload_bg 'cd app && pnpm run build')"

assert_no_op "docker compose logs -f backgrounded" \
  "$(payload_bg 'docker compose logs -f worker')"

assert_no_op "tail -f backgrounded" \
  "$(payload_bg 'tail -f tmp/test.log')"

# ── PASS: quick commands, foreground ──

assert_no_op "ls"                        "$(payload_fg 'ls')"
assert_no_op "git status"                "$(payload_fg 'git status')"
assert_no_op "cat file"                  "$(payload_fg 'cat tmp/foo')"
assert_no_op "tail -n 20 (not -f)"       "$(payload_fg 'tail -n 20 /tmp/log')"
assert_no_op "echo"                      "$(payload_fg "echo 'hello'")"
assert_no_op "./sb psql quick query"     "$(payload_fg 'echo "SELECT 1" | ./sb psql')"
assert_no_op "./sb migrate up"           "$(payload_fg './sb migrate up')"
assert_no_op "./sb config show"          "$(payload_fg './sb config show')"
assert_no_op "./sb upgrade list"         "$(payload_fg './sb upgrade list')"
assert_no_op "./sb upgrade schedule"     "$(payload_fg './sb upgrade schedule v2026.04.0-rc.49')"
assert_no_op "docker compose ps"         "$(payload_fg 'docker compose ps')"
assert_no_op "docker compose logs (no -f)" "$(payload_fg 'docker compose logs worker --tail=50')"
assert_no_op "docker compose up -d"      "$(payload_fg 'docker compose up -d')"
assert_no_op "docker compose up -d svc"  "$(payload_fg 'docker compose up -d db worker')"
assert_no_op "docker compose down"       "$(payload_fg 'docker compose down')"
assert_no_op "timeout=10000ms quick"     "$(payload_timeout 'echo anything' 10000)"
assert_no_op "timeout=30000ms (exactly threshold, not over)" \
  "$(payload_timeout 'echo anything' 30000)"

# ── PASS: non-Bash tools ──

assert_no_op "Read tool" \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'
assert_no_op "Agent tool" \
  '{"tool_name":"Agent","tool_input":{"name":"x"}}'

# ── Commit-body false-positive prevention ──
# git commit -m "..." bodies are stripped before pattern-matching; a
# command string documented inside a commit message must NOT block the commit.

assert_no_op "git commit -m with ./dev.sh test in body → no-op (body stripped)" \
  "$(payload_fg 'git commit -m "fix: example of running ./dev.sh test fast as documentation"')"

# Heredoc form: $(cat <<'EOF'\n...\nEOF\n) — after tr normalization the body
# is a single line; the "double-quote" sed strip removes the entire -m "...".
assert_no_op "git commit with heredoc body containing ./sb install → no-op (body stripped)" \
  "$(payload_fg $'git commit -m "$(cat <<\'EOF\'\nMulti-line commit body with embedded\n./sb install reference\nEOF\n)"')"

# Bare long-running command (not inside a commit) — unchanged existing behaviour.
assert_deny "bare ./dev.sh test fast (no commit wrapper) → still DENY" \
  "$(payload_fg './dev.sh test fast')"

# -F flag: the external file path is stripped, leaving only 'git commit'.
assert_no_op "git commit -F file → no-op (-F path stripped)" \
  "$(payload_fg 'git commit -F tmp/commit-msg.txt')"

# -F - <<EOF heredoc-to-stdin: the heredoc body is stripped (to line end), so a
# long-running command documented in the body no longer false-fires the commit.
assert_no_op "git commit -F - <<EOF body with ./sb install → no-op (heredoc stripped)" \
  "$(payload_fg $'git commit -F - <<\'EOF\'\nfix: documents running ./sb install in the body\nEOF')"

# -m "..." with an EMBEDDED ESCAPED QUOTE before a pattern: the escaped-quote-aware
# strip ([^"\]|\\.)* matches through \" so the whole body is removed (previously the
# [^"]* strip stopped at the first \" and the tail false-matched).
assert_no_op "git commit -m with escaped quote + ./dev.sh test in body → no-op" \
  "$(payload_fg 'git commit -m "fix the \"./dev.sh test\" doc example, see ./sb install"')"

# ── Known false-positive (documented) ──
# The regex matches the pattern text even when quoted inside `echo`.
# We accept this — the deny message is clear and the caller can either
# rephrase the echo or just background it (harmless for a quick echo).

assert_deny "known false-positive: echo with quoted pattern text" \
  "$(payload_fg 'echo "./dev.sh test is slow"')"

# ── Report ─────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo "────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
  echo "ALL GREEN: $PASS / $TOTAL tests passed"
  exit 0
else
  echo "FAILED: $FAIL / $TOTAL tests failed ($PASS passed)"
  exit 1
fi
