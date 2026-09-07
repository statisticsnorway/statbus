#!/bin/bash
# Arc: preswap-fetch-returned-error  (STATBUS-339 H3, KindError)
# judge = base_sha release binary; judged = signed B candidate.
# Expected terminal state: failed / GIT_FETCH_FAILED_RETRYABLE, without rollback.
#
# A→B returns an error at executeUpgrade's real preswap target-object fetch site.
# The failure occurs after the ownership flag but before read-only, maintenance,
# backup, checkout, or binary swap. A keeps serving; the typed failure row is the
# retryability contract. Re-scheduling B without injection must then complete.
# Inputs: BASE_SHA, B_FULL, B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name=$1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-preswap-fetch-returned-error}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="preswap-fetch-returns-error"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

row_field() {
    local expression="$1"
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT ${expression} FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"
}
sb_version() {
    VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" 2>/dev/null | tr -d '\r' || echo ""
}

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: preswap-fetch-returned-error (KindError; direct failed row)"
echo "  A=${BASE_SHA:0:8} B=${B_FULL:0:8} inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
SB_VERSION_BEFORE=$(sb_version)
assert_health_passes "$VM_NAME"

echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"
arc_install_dispatch_with_inject "$INJECT_CLASS" &
DISPATCH_PID=$!
sleep 2
assert_health_passes "$VM_NAME"
wait "$DISPATCH_PID"

[ "$(row_field state)" = "failed" ] || { echo "✗ returned fetch error did not end failed" >&2; exit 1; }
[ "$(row_field failure_code)" = "GIT_FETCH_FAILED_RETRYABLE" ] || { echo "✗ wrong failure_code" >&2; exit 1; }
[ "$(row_field 'rolled_back_at IS NULL')" = "t" ] || { echo "✗ rollback ran for pre-maintenance failure" >&2; exit 1; }
[ "$(row_field 'backup_path IS NULL')" = "t" ] || { echo "✗ backup was recorded before preswap fetch failure" >&2; exit 1; }
assert_flag_file_absent "$VM_NAME"
[ "$(sb_version)" = "$SB_VERSION_BEFORE" ] || { echo "✗ baseline binary changed on returned fetch error" >&2; exit 1; }
VM_EXEC bash -c "test ! -e ~/statbus/tmp/maintenance.html && test ! -e ~/statbus/tmp/maintenance"
assert_health_passes "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

echo "── re-schedule the same candidate without injection ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"
RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 timeout $INSTALL_BUDGET_S ./sb install --non-interactive --trust-github-user jhf" || RC=$?
[ "$RC" = "0" ] || { echo "✗ clean retry failed (rc=$RC)" >&2; exit 1; }
[ "$(row_field state)" = "completed" ] || { echo "✗ clean retry did not complete" >&2; exit 1; }
assert_health_passes "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"

echo "PASS: returned preswap fetch error is typed, non-destructive, flag-clean, and retryable"
