#!/usr/bin/env bash
# dev.sh run_bounded bounds a command with a timer. When the command finishes
# first, run_bounded must leave no process behind: every process it started
# inherits the caller's open files, and the test-run lock is one of them (fd 9),
# so a process that outlives run_bounded holds the lock after dev.sh has exited.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH_ROOT=${JCODE_SCRATCH_DIR:-$REPO_ROOT/tmp}
work=$(mktemp -d "$SCRATCH_ROOT/dev-run-bounded.XXXXXX")

# run_bounded exactly as dev.sh defines it.
sed -n '/^    run_bounded() {$/,/^    }$/p' "$REPO_ROOT/dev.sh" > "$work/run_bounded.sh"
[ -s "$work/run_bounded.sh" ] || { echo "FAIL: run_bounded not found in dev.sh"; exit 1; }
# shellcheck disable=SC1091
source "$work/run_bounded.sh"

lock="$work/lock"
: > "$lock"
exec 9>>"$lock"
# The command outlasts the timer's start, so the timer's sleep is running when
# run_bounded stops the timer, as for every real command dev.sh bounds.
run_bounded 30 "$work/command.log" sleep 0.3
exec 9>&-
sleep 0.5
holders=$(lsof -t "$lock" 2>/dev/null | wc -l | tr -d ' ' || true)
echo "processes holding the lock file after run_bounded returned: $holders"
test "$holders" -eq 0
echo "PASS: run_bounded left no process holding the caller's open files"
