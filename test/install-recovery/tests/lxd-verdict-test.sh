#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/install-recovery/lxd/verdict.sh"
log=$(mktemp)
trap 'rm -f "$log"' EXIT
check() {
    local expected=$1 rc=$2 actual
    actual=$(lxd_scenario_verdict "$log" "$rc")
    [ "$actual" = "$expected" ] || { echo "FAIL: expected $expected, got $actual" >&2; exit 1; }
}
printf 'diagnostic noise\nPASS: final assertion\n' > "$log"
check PASS 0
printf 'PASS: earlier assertion\nFAIL: final assertion\n' > "$log"
check FAIL 0
check FAIL 1
printf 'FAIL: earlier assertion\nPASS: final assertion\n' > "$log"
check PASS 0
check ERROR 1
printf 'diagnostic quotes "PASS: not an assertion"\n' > "$log"
check INVALID 0
check ERROR 1
printf 'diagnostic quotes "FAIL: not an assertion"\n' > "$log"
check ERROR 1
echo 'PASS: LXD verdict classification'
