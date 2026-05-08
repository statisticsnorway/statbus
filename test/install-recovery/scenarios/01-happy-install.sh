#!/bin/bash
# Scenario 01: happy-install
#
# Baseline. Fresh VM → install statbus → assert health passes + step 9
# completed + step 15 completed. Validates the harness skeleton itself
# without involving any wedge.
#
# Usage:
#   ./test/install-recovery/scenarios/01-happy-install.sh <vm_name>
#
# Optional env:
#   KEEP_VM=1            Leave VM running on failure for debugging
#   INSTALL_VERSION=...  Use a specific release version instead of local sb

set -euo pipefail

VM_NAME="${1:-statbus-recovery-01}"
INSTALL_VERSION="${INSTALL_VERSION:-}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"

trap 'cleanup_vm "$VM_NAME"' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 01: happy-install"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# 2. Install (no wedge)
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 3. Assertions
assert_health_passes "$VM_NAME"
assert_step9_completed "$VM_NAME"
assert_step15_completed "$VM_NAME"
assert_systemd_active "$VM_NAME"

echo ""
echo "PASS: 01-happy-install"
