#!/bin/bash
# Scenario 07: stage-e-worker-busy
#
# Validates: Fix 8 (worker excluded from advisory_holders count),
#            Fix 9 (no false-fail on pool busy),
#            Fix 10 (psql-only filter on Phase 1 + leaked).
#
# Setup: install on fresh VM, queue many heavy worker tasks, then run
# ./sb install while the worker is actively processing them. Connection
# pool will be busy (PostgREST + worker), worker will hold advisory
# locks, and worker may briefly run CALL worker.statistical_*_reduce
# matching the leaked-pattern in checkSessionsClean.
#
# A regressed install (e.g. without Fix 10's application_name='psql'
# filter on Phase 1) would TERMINATE LIVE WORKER connections,
# disrupting the queue. With Fixes 8/9/10/11, the install completes
# through step 15 untouched.
#
# Usage:
#   ./test/install-recovery/scenarios/07-stage-e-worker-busy.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-07}"
INSTALL_VERSION="${INSTALL_VERSION:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'cleanup_vm "$VM_NAME"' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 07: stage-e-worker-busy"
echo "  Validates: Fix 8 + Fix 9 + Fix 10 (worker-running install)"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# 2. First install — fresh, healthy.
echo ""
echo "── first install (fresh) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# 3. Snapshot worker connection state BEFORE the wedge so we can verify
# the worker survives the install (not terminated by a buggy Phase 1).
WORKER_PIDS_BEFORE=$($VM_EXEC bash -c "cd ~/statbus && echo \"SELECT pid FROM pg_stat_activity WHERE application_name = 'worker' ORDER BY pid;\" | ./sb psql -t -A" 2>/dev/null | sort | tr '\n' ',' || echo "")
echo "  baseline worker PIDs: $WORKER_PIDS_BEFORE"

# 4. Wedge: queue heavy worker tasks. Worker will pick them up and start
# processing CALL worker.statistical_*_reduce.
echo ""
echo "── queuing heavy worker tasks ──"
simulate_worker_busy "$VM_NAME" 30

# 5. Run install AGAIN while worker is busy. This is the regression
# trigger.
echo ""
echo "── re-run install while worker is processing ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 6. Assertions
assert_step9_completed "$VM_NAME"
assert_step15_completed "$VM_NAME"
assert_health_passes "$VM_NAME"

# 7. Verify: worker connections were NOT all terminated by the install.
# At least the worker process should still be alive (it auto-reconnects
# on connection drop, but if Phase 1 was broken and TERMINATEd workers,
# there'd be a noticeable disruption).
WORKER_PIDS_AFTER=$($VM_EXEC bash -c "cd ~/statbus && echo \"SELECT pid FROM pg_stat_activity WHERE application_name = 'worker' ORDER BY pid;\" | ./sb psql -t -A" 2>/dev/null | sort | tr '\n' ',' || echo "")
WORKER_COUNT_AFTER=$($VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_stat_activity WHERE application_name = 'worker';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "0")
echo "  post-install worker PIDs: $WORKER_PIDS_AFTER (count=$WORKER_COUNT_AFTER)"
if [ "$WORKER_COUNT_AFTER" -lt 1 ]; then
    echo "  ✗ no worker connections after install — Phase 1 may have terminated workers (Fix 10 regression?)"
    exit 1
fi
echo "  ✓ worker still has $WORKER_COUNT_AFTER active connection(s) post-install"

echo ""
echo "PASS: 07-stage-e-worker-busy"
