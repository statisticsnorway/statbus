#!/bin/bash
# Scenario 09: bool-text-regression
#
# Catches Fix 11-class parsing bugs. The setup: install on a fresh VM,
# wait for the worker to come up and start processing tasks (so it's
# holding advisory locks legitimately, with application_name='worker'),
# then run `./sb install` AGAIN — the install-fixup phase. Assert that
# step 9 (Database sessions) passes and the install completes through
# step 15.
#
# This is exactly the case that exposed Fix 11 on rune. checkSessionsClean
# was always returning false (because of the bool::text bug rendering as
# 'true' instead of 't' — the Go-side `parts[1] == "t"` always returned
# false). The install-fixup post-upgrade always failed at step 9, blocking
# the path to step 15's systemd reset-failed.
#
# A working install today should pass this scenario in <2 min after
# bootstrap. A regressed install (e.g. someone re-introducing a
# bool-to-text cast in checkSessionsClean's healthy column) will hang
# at step 9 with "connection pool still saturated" and the assertion
# fails.
#
# Usage:
#   ./test/install-recovery/scenarios/09-bool-text-regression.sh <vm_name>
#
# Optional env:
#   KEEP_VM=1            Leave VM running on failure for debugging
#   INSTALL_VERSION=...  Use a specific release version instead of local sb

set -euo pipefail

VM_NAME="${1:-statbus-recovery-09}"
INSTALL_VERSION="${INSTALL_VERSION:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"

trap 'cleanup_vm "$VM_NAME"' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 09: bool-text-regression"
echo "  Validates: Fix 11 (bool::text parsing) + worker-running install"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# 2. First install — happy path, fresh.
echo ""
echo "── first install (fresh, healthy install) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# 3. Wait for worker to be running and processing tasks.
# Worker takes a few seconds to start after install completes.
echo ""
echo "── waiting for worker to be holding advisory locks legitimately ──"
for i in $(seq 1 12); do
    HOLDERS=$($VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a ON l.pid = a.pid WHERE l.locktype = 'advisory' AND l.granted AND a.application_name = 'worker';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "0")
    if [ "$HOLDERS" -ge 1 ]; then
        echo "  ✓ worker is holding $HOLDERS advisory lock(s) — ready"
        break
    fi
    echo "  … waiting for worker advisory locks (attempt $i/12, count=$HOLDERS)"
    sleep 5
done

# 4. RE-RUN install. The install-fixup phase or step-table re-run is the
# exact code path where Fix 11 was broken. Worker is still running and
# holding advisory locks — bool-text-bug installs would fail here at
# step 9.
echo ""
echo "── re-run install while worker is busy (exercises checkSessionsClean recheck) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 5. Assertions — must reach step 15.
assert_step9_completed "$VM_NAME"
assert_step15_completed "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_active "$VM_NAME"

echo ""
echo "PASS: 09-bool-text-regression"
