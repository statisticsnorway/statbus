#!/usr/bin/env bash
# STATBUS-425 M3b review C1: arc_wait_unit_active must honour its budget in
# EVERY branch (old boot still active, unreadable/unparsable start timestamp,
# inactive), and still succeed on a new boot / plain active. Runs the REAL
# function extracted from arc-helpers.sh against a stubbed VM_EXEC; offline.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
HELPERS="$ROOT/test/install-recovery/lib/arc-helpers.sh"
fn=$(awk '/^arc_wait_unit_active\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$HELPERS")
[ -n "$fn" ] || { echo "FAIL: could not extract arc_wait_unit_active" >&2; exit 1; }

# Stub scenario knobs, read by VM_EXEC.
STUB_STATE=active STUB_START_TS='Tue 2026-09-29 12:20:25 UTC' STUB_EPOCH=1000
VM_EXEC() {
    local joined="$*"
    case "$joined" in
        *is-active*) echo "$STUB_STATE" ;;
        *ExecMainStartTimestamp*) echo "$STUB_START_TS" ;;
        *"date -d"*) echo "$STUB_EPOCH" ;;
        *) : ;;
    esac
}
sleep() { command sleep 0.2; }   # keep the real loop shape, shrink the pause
eval "$fn"

fails=0
# run_case NAME EXPECT_RC AFTER_EPOCH — runs in a subshell with a hard
# watchdog: rc 124 means the budget was NOT enforced (the C1 defect).
run_case() {
    local name="$1" want="$2" after="$3" pid wd rc out
    out=$(mktemp)
    ( arc_wait_unit_active 1 fake.service "$after" ) >"$out" 2>&1 &
    pid=$!
    ( command sleep 15; kill -9 "$pid" 2>/dev/null ) &
    wd=$!
    wait "$pid" 2>/dev/null; rc=$?
    kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
    [ "$rc" -eq 137 ] && rc=124
    if [ "$rc" -eq "$want" ]; then echo "ok   $name (rc=$rc)"
    else echo "FAIL $name: rc=$rc want $want"; sed 's/^/     /' "$out"; fails=$((fails+1)); fi
    rm -f "$out"
}

STUB_STATE=active STUB_EPOCH=1000; run_case "old boot still active -> budget rc=1" 1 2000
STUB_STATE=active STUB_START_TS=n/a; run_case "start timestamp unreadable -> budget rc=1" 1 2000
STUB_STATE=active STUB_START_TS='Tue 2026-09-29 12:20:25 UTC' STUB_EPOCH=garbage; run_case "epoch not numeric -> budget rc=1" 1 2000
STUB_STATE=active STUB_EPOCH=3000 STUB_START_TS='Tue 2026-09-29 12:20:25 UTC'; run_case "new active invocation -> rc=0" 0 2000
STUB_STATE=active; run_case "active, no after_ts -> rc=0" 0 ""
STUB_STATE=inactive; run_case "inactive -> budget rc=1" 1 2000
[ "$fails" -eq 0 ] && echo "PASS: arc_wait_unit_active budget/branch behaviour" || exit 1
