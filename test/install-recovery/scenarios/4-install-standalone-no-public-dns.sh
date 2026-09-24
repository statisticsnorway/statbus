#!/usr/bin/env bash
# STATBUS-389 B3: only the public-DNS recommendation is in scope here.
# A private-certificate selection and working HTTPS are owned by STATBUS-399,
# and this scenario intentionally does not claim those later criteria pass.
set -euo pipefail
VM_NAME="${1:-statbus-recovery-4-install-standalone-no-public-dns}"
HARNESS_DEPLOYMENT_MODE=standalone
HARNESS_SITE_DOMAIN=statbus-no-public-dns.invalid
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
INSTALL_TARGET_TAG="${INSTALL_TARGET_TAG:-$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)}"
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
[ "$TARGET_SHA" = "$(git -C "$REPO_ROOT" rev-parse HEAD)" ] || { echo 'candidate tag must point at HEAD' >&2; exit 1; }
source "$LIB_DIR/vm-bootstrap.sh"
trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_TARGET_TAG"
INSTALL_LOG=$(mktemp)
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG" >"$INSTALL_LOG" 2>&1 || true
# Public DNS must be queried rather than silently accepting the local hosts file.
grep -Eqi 'not confirmed in public DNS|no public DNS|absent from public DNS' "$INSTALL_LOG" || { cat "$INSTALL_LOG" >&2; echo 'missing public DNS assessment' >&2; exit 1; }
grep -Eqi 'automatic public certificate cannot be promised' "$INSTALL_LOG" || { cat "$INSTALL_LOG" >&2; echo 'missing certificate recommendation' >&2; exit 1; }
! grep -Eqi 'automatic public certificate.*(will|can) (be |now )?issued' "$INSTALL_LOG" || { cat "$INSTALL_LOG" >&2; exit 1; }
rm -f "$INSTALL_LOG"
echo 'PASS: public DNS absence identified, automatic certificate not promised; private-certificate HTTPS requires STATBUS-399'
