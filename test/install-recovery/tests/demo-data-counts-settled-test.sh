#!/bin/bash
# Offline regression test: the demo-data count comparison judges the settled
# state. rc.02 LXD run 41108121046 (0-https-only-egress) read
# statistical_history=674 of 1430 while the worker ran the full rebuild a
# migration had scheduled; the counts returned to the snapshot once the
# derive finished. A real difference must still fail after the drain.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/install-recovery/lib/assertions.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-counts-settled.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
export HARNESS_ROOT="$TMP_ROOT"
export HARNESS_DB_QUERY_RETRY_INTERVAL_S=0
VM_NAME=test-vm
VM_IP=127.0.0.1
SSH_OPTS=(-o MockOption=yes)
SNAPSHOT='statistical_unit=126,legal_unit=23,establishment=50,statistical_history=1430'
MID_REBUILD='statistical_unit=126,legal_unit=23,establishment=50,statistical_history=674'

# The guest's count query answers from a queue of readings, one per call.
ssh() {
    local reading
    reading=$(head -n1 "$TMP_ROOT/readings")
    sed -i.bak '1d' "$TMP_ROOT/readings"
    printf '%s\n' "$reading"
}
wait_for_worker_quiesce() {
    echo drained >> "$TMP_ROOT/quiesce-calls"
    return 0
}

# 1. Mid-rebuild reading, then the settled reading equals the snapshot: pass.
printf '%s\n%s\n' "$MID_REBUILD" "$SNAPSHOT" > "$TMP_ROOT/readings"
: > "$TMP_ROOT/quiesce-calls"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$SNAPSHOT" > "$TMP_ROOT/out1"
grep -q 'match snapshot after the worker drained' "$TMP_ROOT/out1"
[ "$(wc -l < "$TMP_ROOT/quiesce-calls" | tr -d ' ')" = 1 ]
echo 'PASS: counts read mid-rebuild are judged after the worker drains'

# 2. Equal on the first reading: pass without waiting.
printf '%s\n' "$SNAPSHOT" > "$TMP_ROOT/readings"
: > "$TMP_ROOT/quiesce-calls"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$SNAPSHOT" > "$TMP_ROOT/out2"
grep -q 'demo-data counts match snapshot (' "$TMP_ROOT/out2"
[ ! -s "$TMP_ROOT/quiesce-calls" ]
echo 'PASS: equal counts pass at once, without waiting for the worker'

# 3. Still different after the drain: fail with the settled reading.
printf '%s\n%s\n' "$MID_REBUILD" "$MID_REBUILD" > "$TMP_ROOT/readings"
if assert_demo_data_counts_match_snapshot "$VM_NAME" "$SNAPSHOT" > "$TMP_ROOT/out3"; then
    echo 'FAIL: a difference that survives the drain was accepted' >&2
    exit 1
fi
grep -q "actual:   $MID_REBUILD" "$TMP_ROOT/out3"
echo 'PASS: a difference that survives the drain fails'

# 4. Derived history empty right after the upgrade (the migration dropped the
#    old tables and scheduled the rebuild), filled once the worker drains: pass.
#    v2026.11.2-rc.01 Test Smoke 42395943541 read statistical_history=0 3 s after
#    the upgrade completed.
EMPTY_HISTORY='statistical_unit=126,legal_unit=23,establishment=50,statistical_history=0'
printf '%s\n%s\n' "$EMPTY_HISTORY" "$SNAPSHOT" > "$TMP_ROOT/readings"
: > "$TMP_ROOT/quiesce-calls"
assert_demo_data_present "$VM_NAME" > "$TMP_ROOT/out4"
grep -q 'all demo-data tables populated' "$TMP_ROOT/out4"
[ "$(wc -l < "$TMP_ROOT/quiesce-calls" | tr -d ' ')" = 1 ]
echo 'PASS: an empty derived table is judged after the worker drains'

# 5. Still empty after the drain: the catastrophic-loss indicator fires.
printf '%s\n%s\n' "$EMPTY_HISTORY" "$EMPTY_HISTORY" > "$TMP_ROOT/readings"
if assert_demo_data_present "$VM_NAME" > "$TMP_ROOT/out5"; then
    echo 'FAIL: a table still empty after the drain was accepted' >&2
    exit 1
fi
grep -q 'public.statistical_history has 0 rows' "$TMP_ROOT/out5"
echo 'PASS: a table still empty after the drain fails'
