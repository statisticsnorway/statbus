#!/bin/bash
# Candidate install, full uninstall, fresh install on the same VM.
set -euo pipefail
VM_NAME="${1:-statbus-recovery-6-uninstall-reinstall}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
INSTALL_TARGET_TAG="${INSTALL_TARGET_TAG:-$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)}"
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
[[ $TARGET_SHA == "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]] || { echo 'Candidate tag must point at HEAD' >&2; exit 1; }
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"
trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_TARGET_TAG"
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG"
VM_EXEC bash -c 'cd ~/statbus && STATBUS_UNINSTALL_CONFIRM=yes-delete-everything ./sb uninstall'
VM_EXEC bash -c 'test ! -e ~/statbus && test -z "$(docker ps -aq --filter name=statbus)" && test -z "$(docker volume ls -q --filter name=statbus)"'
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG"
VM_EXEC bash -c 'cd ~/statbus && ./sb db status'
echo 'PASS: uninstall removed checkout, containers and volumes without sudo, and a fresh reinstall on the same box succeeded'
