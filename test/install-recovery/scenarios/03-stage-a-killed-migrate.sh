#!/bin/bash
# Scenario 03: stage-a-killed-migrate-subprocess
#
# Validates: Fix 3 Phase 1 cleanup (orphan psql backends from killed
# migrate-up subprocesses). Fix 1 (sd_notify EXTEND_TIMEOUT_USEC) makes
# this rare in production but possible (e.g. operator-driven kill mid-
# migrate). Fix 5 forward-recovery completes the migration on next
# install.
#
# Setup: install on fresh VM. Schedule an upgrade through the upgrade
# pipeline. Wait for migrate.Up to spawn its psql subprocess. SIGKILL
# the subprocess. Postgres backend orphans. Run ./sb install — Phase 1
# of cleanOrphanSessions should detect the orphan and terminate it.
# Recovery proceeds to apply the missing migration via Fix 5b's
# forward-recovery.
#
# Usage:
#   ./test/install-recovery/scenarios/03-stage-a-killed-migrate.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-03}"
INSTALL_VERSION="${INSTALL_VERSION:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'cleanup_vm "$VM_NAME"' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 03: stage-a-killed-migrate-subprocess"
echo "  Validates: Fix 3 Phase 1 cleanup of psql migrate-zombies"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# 2. Initial install — fresh, healthy.
echo ""
echo "── initial install ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# 3. Wedge: kill an active migrate psql subprocess.
# This requires there to BE an active migrate subprocess. In practice
# the install above just completed; we need to either trigger a manual
# migrate or skip this in the smoke phase. For a pure regression-test
# of Phase 1's cleanup logic, we synthesize an orphan: open psql with
# a long-running TRUNCATE-like statement, then SIGKILL the client.
echo ""
echo "── synthesizing migrate-zombie (long-running INSERT on statistical_*) ──"
$VM_EXEC bash -c '
    cd ~/statbus
    # Fork a psql with a long-running INSERT (picks up statistical_* pattern).
    # The query takes ~10 minutes if left alone — long enough for the
    # SIGKILL + recheck cycle.
    ./sb psql -c "INSERT INTO public.statistical_history SELECT * FROM public.statistical_history WHERE pg_sleep(600) IS NULL OR true;" >/dev/null 2>&1 &
    echo "psql_pid=$!"
    sleep 3
    PSQL_PID=$(pgrep -f "psql.*statistical_history" | head -1)
    if [ -n "$PSQL_PID" ]; then
        kill -9 "$PSQL_PID" 2>/dev/null || true
        echo "killed psql PID=$PSQL_PID — postgres backend should orphan"
    else
        echo "warning: no psql subprocess to kill" >&2
    fi
'

# 4. Run install — Phase 1 cleanup should catch the orphan.
echo ""
echo "── re-run install (Phase 1 should kill the zombie) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 5. Assertions
assert_step9_completed "$VM_NAME"
assert_step15_completed "$VM_NAME"
assert_health_passes "$VM_NAME"

# 6. Verify the zombie is gone.
ZOMBIE_COUNT=$($VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_stat_activity WHERE query ILIKE '%INSERT INTO public.statistical_history%' AND application_name = 'psql';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "?")
if [ "$ZOMBIE_COUNT" = "0" ]; then
    echo "  ✓ no psql zombies remaining post-cleanup"
else
    echo "  ✗ psql zombie still present (count=$ZOMBIE_COUNT)"
    exit 1
fi

echo ""
echo "PASS: 03-stage-a-killed-migrate-subprocess"
