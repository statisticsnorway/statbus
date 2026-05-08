#!/bin/bash
# Scenario 04: stage-b-pool-exhaustion
#
# Validates: Fix 3's docker-exec bypass in cleanOrphanSessions when
# max_connections is saturated. The host-side psql (migrate.PsqlCommand)
# will fail with "FATAL: too many clients", but cleanOrphanSessions's
# Phase 2 uses `docker compose exec -T db psql -U postgres` which runs
# as the postgres OS user inside the container with peer auth → gets
# superuser → reserved-slot eligible → bypasses pool exhaustion.
#
# Setup: install on fresh VM. Open enough idle psql sessions to saturate
# max_connections. Run ./sb install — Phase 1's docker-exec cleanup
# should still terminate appropriate backends.
#
# Usage:
#   ./test/install-recovery/scenarios/04-stage-b-pool-exhaustion.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-04}"
INSTALL_VERSION="${INSTALL_VERSION:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'cleanup_vm "$VM_NAME"' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 04: stage-b-pool-exhaustion"
echo "  Validates: Fix 3 docker-exec bypass when max_clients saturated"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# 2. Initial install
echo ""
echo "── initial install ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# 3. Wedge: saturate max_connections with idle psql sessions.
# The wedge-helpers' simulate_pool_exhaustion handles the math; with
# max_connections=30 by default, opening 28 sessions leaves 2 slots
# (reserved superuser + the psql probe).
echo ""
simulate_pool_exhaustion "$VM_NAME" 28

# 4. Verify host-side psql is now blocked.
echo ""
echo "── verify external psql blocked by saturated pool ──"
HOST_PSQL_RESULT=$($VM_EXEC bash -c "cd ~/statbus && ./sb psql -c 'SELECT 1' 2>&1" || true)
if echo "$HOST_PSQL_RESULT" | grep -q "too many clients"; then
    echo "  ✓ external psql blocked: '$HOST_PSQL_RESULT'"
else
    echo "  ⚠ external psql still works — pool exhaustion may not have engaged"
fi

# 5. Run install — should succeed via docker-exec bypass.
echo ""
echo "── re-run install (Fix 3 docker-exec bypass) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 6. Assertions
assert_step9_completed "$VM_NAME"
assert_step15_completed "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 04-stage-b-pool-exhaustion"
