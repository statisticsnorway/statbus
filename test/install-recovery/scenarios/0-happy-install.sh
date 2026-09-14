#!/bin/bash
# Scenario: 0-happy-install
#
# Fresh Ubuntu VM → the candidate's real install.sh → a healthy StatBus at
# the candidate, using its tagged sb-linux-<arch> release asset and published
# images at its commit. Proves release-ladder.md rung 4, not a baseline hop.
# This is "install-works" in STATBUS-359's pending naming scheme.
# Assert the installed binary identity, newest public.upgrade row, and health
# on the box. Home-level unattended inputs preserve an absent ~/statbus until
# install.sh itself clones it through FRESH. No pre-clone or custom procurement.
#
# Usage:
#   ./test/install-recovery/scenarios/0-happy-install.sh <vm_name>
#
# Optional env:
#   KEEP_VM=1             Leave VM running on failure for debugging
#   INSTALL_TARGET_TAG=... Release-shaped tag at HEAD (default: newest at HEAD)

set -euo pipefail

VM_NAME="${1:-statbus-recovery-0-happy-install}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
# Validate the candidate BEFORE provisioning. Untagged commits cannot prove a
# release-asset install. An old INSTALL_VERSION override must not select a baseline.
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
INSTALL_TARGET_TAG="${INSTALL_TARGET_TAG:-$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)}"
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null || {
    echo "ERROR: 0-happy-install needs a release-shaped INSTALL_TARGET_TAG at HEAD" >&2
    exit 1
}
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
if [ "$TARGET_SHA" != "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]; then
    echo "ERROR: INSTALL_TARGET_TAG '$INSTALL_TARGET_TAG' does not point at HEAD" >&2
    exit 1
fi
if [ -n "${INSTALL_VERSION:-}" ] && [ "$INSTALL_VERSION" != "$INSTALL_TARGET_TAG" ]; then
    echo "ERROR: 0-happy-install installs the candidate, not INSTALL_VERSION=$INSTALL_VERSION" >&2
    exit 1
fi
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 0-happy-install"
echo "  Release selected for clean install: $INSTALL_TARGET_TAG"
echo "════════════════════════════════════════════════════════════════"

# 1. Bootstrap VM
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_TARGET_TAG"

# 2. Install (no wedge)
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG"

# 3. Assertions against the box, never inferred from installer exit status.
BINARY_IDENTITY=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version")
EXPECTED_BINARY="sb version $INSTALL_TARGET_TAG (commit ${TARGET_SHA:0:8})"
if [ "$BINARY_IDENTITY" != "$EXPECTED_BINARY" ]; then
    echo "✗ installed binary mismatch: expected='$EXPECTED_BINARY' actual='$BINARY_IDENTITY'" >&2
    exit 1
fi
echo "  ✓ installed binary: $BINARY_IDENTITY"

# Deliberately inspect the newest row, not a WHERE that could hide an install
# of the wrong candidate. Empty rows, query/SSH failures, and rollback all fail.
UPGRADE_IDENTITY=$(VM_EXEC bash -c "cd ~/statbus && ./sb psql -X -v ON_ERROR_STOP=1 -t -A -c \"SELECT commit_version, commit_sha, state FROM public.upgrade ORDER BY id DESC LIMIT 1;\"")
EXPECTED_UPGRADE="$INSTALL_TARGET_TAG|$TARGET_SHA|completed"
if [ "$UPGRADE_IDENTITY" != "$EXPECTED_UPGRADE" ]; then
    echo "✗ newest public.upgrade row mismatch: expected='$EXPECTED_UPGRADE' actual='$UPGRADE_IDENTITY'" >&2
    exit 1
fi
echo "  ✓ newest public.upgrade row: $UPGRADE_IDENTITY"

assert_health_passes "$VM_NAME"
assert_step9_completed "$VM_NAME"
assert_step_upgrade_service_completed "$VM_NAME"
assert_systemd_active "$VM_NAME"

echo ""
echo "PASS: 0-happy-install"
