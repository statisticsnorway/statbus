#!/bin/bash
# Scenario 06: stage-d-empty-app-advisory
#
# Validates: Fix 6 Phase 2 PID-liveness probe (terminates dead-PID
# zombies holding the migrate_up advisory lock with
# application_name='statbus-migrate-{dead_pid}') AND empty-app-name
# catch-all (terminates pre-Fix-6 zombies with empty application_name).
#
# This is the EXACT shape of rune's PID 9962: idle session, holds
# migrate_up advisory lock, application_name='' (no marker because the
# rc.03 binary that opened it didn't have Fix 6a's session tagging).
#
# Setup: open psql with empty application_name explicitly, take the
# migrate_up advisory lock, sleep. SIGKILL the script. The postgres
# backend remains, idle, holding the lock. Run ./sb install — Phase 2
# should identify the empty-app-name holder, treat as unidentified
# zombie, and terminate it.
#
# Usage:
#   ./test/install-recovery/scenarios/06-stage-d-empty-app-advisory.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-06}"
INSTALL_VERSION="${INSTALL_VERSION:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'cleanup_vm "$VM_NAME"' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 06: stage-d-empty-app-advisory"
echo "  Validates: Fix 6 Phase 2 PID-liveness + empty-app-name catch-all"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# 2. Initial install
echo ""
echo "── initial install ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# 3. Wedge: create empty-app-name advisory zombie (PID 9962-shaped).
echo ""
simulate_advisory_zombie_empty_app "$VM_NAME"

# 4. Verify the zombie is present.
echo ""
echo "── verify zombie present (empty app_name + advisory lock) ──"
ZOMBIE_COUNT=$($VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a ON l.pid = a.pid WHERE l.locktype = 'advisory' AND l.granted AND COALESCE(a.application_name, '') = '' AND a.pid <> pg_backend_pid();\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "?")
echo "  zombie count: $ZOMBIE_COUNT"
if [ "$ZOMBIE_COUNT" -lt 1 ]; then
    echo "  ⚠ no empty-app-name advisory zombie present — wedge didn't engage (TCP keepalives may have reaped it already)"
fi

# 5. Run install — Phase 2 should terminate it.
echo ""
echo "── re-run install (Fix 6 Phase 2 should kill the zombie) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 6. Assertions
assert_step9_completed "$VM_NAME"
assert_step15_completed "$VM_NAME"
assert_health_passes "$VM_NAME"

# 7. Verify zombie is gone post-install.
ZOMBIE_AFTER=$($VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a ON l.pid = a.pid WHERE l.locktype = 'advisory' AND l.granted AND COALESCE(a.application_name, '') = '' AND a.pid <> pg_backend_pid();\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "?")
if [ "$ZOMBIE_AFTER" = "0" ]; then
    echo "  ✓ no empty-app-name zombies remaining post-install"
else
    echo "  ✗ empty-app-name zombie still present (count=$ZOMBIE_AFTER)"
    exit 1
fi

echo ""
echo "PASS: 06-stage-d-empty-app-advisory"
