#!/bin/bash
# Scenario: 5-install-stage-d-advisory-zombie
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
#   ./test/install-recovery/scenarios/5-install-stage-d-advisory-zombie.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-stage-d-advisory-zombie}"
INSTALL_VERSION="${INSTALL_VERSION:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 5-install-stage-d-advisory-zombie"
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
ZOMBIE_COUNT=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a ON l.pid = a.pid WHERE l.locktype = 'advisory' AND l.granted AND COALESCE(a.application_name, '') = '' AND a.pid <> pg_backend_pid();\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "?")
echo "  zombie count: $ZOMBIE_COUNT"
if [ "$ZOMBIE_COUNT" -lt 1 ]; then
    echo "  ⚠ no empty-app-name advisory zombie present — wedge didn't engage (TCP keepalives may have reaped it already)"
fi

# Capture the SPECIFIC synthetic zombie's backend PID now (before the re-install),
# while it is the only empty-app advisory holder. The post-install check asserts
# THIS pid is gone — NOT "any empty-app advisory holder": the install's own
# boot-migrate legitimately holds the migrate_up advisory lock with an empty
# application_name during step 12, so a broad count trips on it even though Fix 6
# Phase 2 DID kill the zombie (run 27168472969: count=1 with the zombie already killed).
ZOMBIE_PID=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT a.pid FROM pg_locks l JOIN pg_stat_activity a ON l.pid = a.pid WHERE l.locktype = 'advisory' AND l.granted AND COALESCE(a.application_name, '') = '' AND a.pid <> pg_backend_pid() ORDER BY a.backend_start DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "")
echo "  captured synthetic zombie backend PID: ${ZOMBIE_PID:-<none>}"

# 5. Run install — Phase 2 should terminate it.
echo ""
echo "── re-run install (Fix 6 Phase 2 should kill the zombie) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 6. Assertions
assert_step9_completed "$VM_NAME"
assert_step_upgrade_service_completed "$VM_NAME"
assert_health_passes "$VM_NAME"

# 7. Verify the SPECIFIC synthetic zombie backend is gone post-install — by its
# captured PID, NOT "any empty-app advisory holder" (the install's boot-migrate
# holds the migrate_up advisory with an empty app_name legitimately).
if [ -z "$ZOMBIE_PID" ]; then
    echo "  ⚠ no zombie PID was captured (wedge didn't engage) — cannot assert Fix 6 Phase 2; skipping the specific-pid check"
else
    ZOMBIE_AFTER=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_stat_activity WHERE pid = $ZOMBIE_PID;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ "$ZOMBIE_AFTER" = "0" ]; then
        echo "  ✓ synthetic zombie PID $ZOMBIE_PID terminated post-install (Fix 6 Phase 2)"
    else
        echo "  ✗ synthetic zombie PID $ZOMBIE_PID still present post-install (count=$ZOMBIE_AFTER) — Fix 6 Phase 2 did not reap it" >&2
        exit 1
    fi
fi

echo ""
echo "PASS: 5-install-stage-d-advisory-zombie"
