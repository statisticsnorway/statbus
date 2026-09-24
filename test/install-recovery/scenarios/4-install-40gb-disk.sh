#!/usr/bin/env bash
# Scenario: 4-install-40gb-disk
# A 40 GB Ubuntu VM must install without STATBUS_MIN_DISK_GB and retain the
# same policy for later invocations. Requires a tagged candidate and VM.
set -euo pipefail
VM_NAME="${1:-statbus-recovery-4-install-40gb-disk}"
HARNESS_DEPLOYMENT_MODE=private
HARNESS_UPGRADE_CHANNEL=stable
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
INSTALL_TARGET_TAG="${INSTALL_TARGET_TAG:-$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)}"
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
[ "$TARGET_SHA" = "$(git -C "$REPO_ROOT" rev-parse HEAD)" ] || { echo 'candidate tag does not match HEAD' >&2; exit 1; }
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"
trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_TARGET_TAG"
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG"
POLICY=$(VM_EXEC bash -c 'cd ~/statbus && ./sb dotenv -f .env.config get STATBUS_DISK_MIN_GB && ./sb dotenv -f .env.config get STATBUS_DISK_RECOMMENDED_GB')
[ "$POLICY" = $'20\n40' ] || { echo "wrong persisted disk policy: $POLICY" >&2; exit 1; }
VM_EXEC bash -c 'mkdir -p "$HOME/statbus-backups"; docker info --format "Docker data: {{.DockerRootDir}}"; df -h "$(docker info --format "{{.DockerRootDir}}")" "$HOME/statbus-backups"'
assert_health_passes "$VM_NAME"
echo 'PASS: 40 GB installation measured Docker data and backups, retained 20/40 GB policy and serves requests'
