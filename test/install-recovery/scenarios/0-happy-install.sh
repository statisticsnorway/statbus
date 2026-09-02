#!/bin/bash
# Scenario: 0-happy-install
#
# Baseline. Fresh VM → install the newest stable release strictly below the
# target under test (newest-RC fallback) → assert health passes + step 9
# completed + step 15 completed. Validates the harness skeleton itself
# without involving any wedge or a fossilised release pin.
#
# Usage:
#   ./test/install-recovery/scenarios/0-happy-install.sh <vm_name>
#
# Optional env:
#   KEEP_VM=1            Leave VM running on failure for debugging
#   INSTALL_VERSION=...  Explicit release pin; overrides algorithmic selection

set -euo pipefail

VM_NAME="${1:-statbus-recovery-0-happy-install}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
INSTALL_VERSION="${INSTALL_VERSION:-$(select_release_baseline_from_repo "$REPO_ROOT")}"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 0-happy-install"
echo "  Release selected for clean install: $INSTALL_VERSION"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# 2. Install (no wedge)
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# 3. Assertions
assert_health_passes "$VM_NAME"
assert_step9_completed "$VM_NAME"
assert_step_upgrade_service_completed "$VM_NAME"
assert_systemd_active "$VM_NAME"

echo ""
echo "PASS: 0-happy-install"
