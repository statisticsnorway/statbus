#!/usr/bin/env bash
# STATBUS-401: install with an answers file for deployment choices but no
# users file, answer first-administrator questions on a PTY and sign in.
# Requires a tagged candidate, uses a VM, never the host PostgreSQL.
set -euo pipefail
VM_NAME="${1:-statbus-recovery-0-interactive-admin-password}"
HARNESS_DEPLOYMENT_MODE=standalone
HARNESS_UPGRADE_CHANNEL=stable
HARNESS_INTERACTIVE_ADMIN=1
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
INSTALL_TARGET_TAG="${INSTALL_TARGET_TAG:-$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)}"
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
[ "$TARGET_SHA" = "$(git -C "$REPO_ROOT" rev-parse HEAD)" ] || { echo 'candidate tag must point at HEAD' >&2; exit 1; }
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"
trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_TARGET_TAG"
VM_ROOT_EXEC bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y expect >/dev/null'
scp -O "${SSH_OPTS[@]}" "$LIB_DIR/interactive-admin.exp" root@"$VM_IP":/tmp/statbus-admin.exp
VM_ROOT_EXEC bash -c 'chown statbus:statbus /tmp/statbus-admin.exp && chmod 0600 /tmp/statbus-admin.exp'
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG"
assert_health_passes "$VM_NAME"
assert_harness_https_passes "$VM_NAME"
INSTALL_CAPTURE="${HARNESS_ROOT:-$REPO_ROOT}/tmp/install-recovery-${VM_NAME}-install.log"
if grep -qF 'test-install-password-2026' "$INSTALL_CAPTURE" ||
    VM_EXEC bash -c 'cd ~/statbus && grep -F -q test-install-password-2026 tmp/install-last-run-output.txt tmp/install-logs/*.log tmp/upgrade-logs/*.log 2>/dev/null'; then
    echo 'administrator password leaked to terminal or support/install log' >&2
    exit 1
fi
# This script is transferred as a file, never passed through VM_EXEC's
# multi-shell quoting. Neither password nor login response is printed.
VM_SCRIPT_INLINE first-admin-login <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
code=$(curl -sS -o /tmp/first-admin-login-response -w '%{http_code}' -H 'Host: statbus-test.local' -H 'Content-Type: application/json' -d '{"email":"interactive-admin@statbus.org","password":"test-install-password-2026"}' http://127.0.0.1:3010/rest/rpc/login)
[ "$code" = 200 ]
grep -Eq '"is_authenticated"[[:space:]]*:[[:space:]]*true' /tmp/first-admin-login-response
REMOTE
echo 'PASS: administrator password entered twice without echo, logs clean, and /rest/rpc/login authenticates'
