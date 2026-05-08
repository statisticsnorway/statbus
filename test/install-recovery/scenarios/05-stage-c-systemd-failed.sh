#!/bin/bash
# Scenario 05: stage-c-systemd-failed
#
# Validates: Fix 4 (`systemctl --user reset-failed + enable+start` in
# install ladder step 15). Force the upgrade-service unit into `failed`
# state via StartLimitBurst trip (>10 starts in 600s). On the next
# install, step 15 should detect ActiveState=failed + Result=start-limit-hit
# and run reset-failed before enable+start. Without Fix 4 the unit
# stays failed forever and auto-discovery is blocked.
#
# Usage:
#   ./test/install-recovery/scenarios/05-stage-c-systemd-failed.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-05}"
INSTALL_VERSION="${INSTALL_VERSION:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'cleanup_vm "$VM_NAME"' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 05: stage-c-systemd-failed"
echo "  Validates: Fix 4 systemctl reset-failed in install ladder step 15"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# 2. Initial install — sets up the systemd unit.
echo ""
echo "── initial install ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"
assert_systemd_active "$VM_NAME"

# 3. Wedge: trip StartLimitBurst.
echo ""
simulate_systemd_failed "$VM_NAME"

# 4. Verify unit is in failed state.
echo ""
echo "── verify unit is in failed state ──"
STATE=$($VM_EXEC systemctl --user is-active statbus-upgrade@statbus.service 2>&1 | head -1 || true)
RESULT=$($VM_EXEC systemctl --user show statbus-upgrade@statbus.service --property=Result --value 2>/dev/null || true)
echo "  unit state=$STATE result=$RESULT"
if [ "$STATE" != "failed" ] && [ "$STATE" != "activating" ]; then
    echo "  ⚠ expected failed/activating, got '$STATE' — wedge may not have engaged"
fi

# 5. Run install — step 15 should reset-failed + enable+start.
echo ""
echo "── re-run install (Fix 4 reset-failed should fire) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 6. Assertions
assert_step15_completed "$VM_NAME"
assert_systemd_active "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 05-stage-c-systemd-failed"
