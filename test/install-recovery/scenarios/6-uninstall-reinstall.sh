#!/bin/bash
# Candidate install, interactive uninstall keeping users and credentials, then
# a fresh install on the same VM that picks both up (STATBUS-419 AC6).
# LXD_START=installed-candidate
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

# The fixture password proves the same administrator can sign in after the
# reinstall, not merely that a row exists.
LOGIN_PASSWORD=test-install-password-2026
login_on_vm() {
    VM_SCRIPT_INLINE "$1" "$2" "$3" <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
domain=$1
password=$2
code=$(curl -sS --cacert "$HOME/harness-certs/ca.crt" -o /tmp/uninstall-reinstall-login -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"test@statbus.org\",\"password\":\"${password}\"}" \
    "https://${domain}/rest/rpc/login")
[ "$code" = 200 ]
grep -Eq '"is_authenticated"[[:space:]]*:[[:space:]]*true' /tmp/uninstall-reinstall-login
REMOTE
}

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_TARGET_TAG"
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG"

# While installed both files live only inside the checkout.
VM_EXEC bash -c 'test -f ~/statbus/.users.yml && test -f ~/statbus/.env.credentials &&
    test ! -e ~/statbus.users.yml && test ! -e ~/statbus.env.credentials'
DOMAIN=$(VM_EXEC bash -c 'cd ~/statbus && ./sb dotenv -f .env.config get SITE_DOMAIN' | tr -d '\r\n')
[ -n "$DOMAIN" ] || { echo 'FAIL: SITE_DOMAIN is empty' >&2; exit 1; }
assert_health_passes "$VM_NAME"
login_on_vm first-admin-login "$DOMAIN" "$LOGIN_PASSWORD"
CREDENTIALS_SHA=$(VM_EXEC bash -c 'sha256sum ~/statbus/.env.credentials | cut -d" " -f1' | tr -d '\r\n')

# Interactive uninstall on a PTY: keep the users (Enter), keep the
# credentials (Enter), delete the database dumps (Y) so the whole checkout
# goes, then confirm the plan.
VM_EXEC bash -c 'cd ~/statbus && printf "\n\nY\nDELETE\n" | script -qec "./sb uninstall" /dev/null'
VM_EXEC bash -c 'test ! -e ~/statbus && test -f ~/statbus.users.yml && test -f ~/statbus.env.credentials'
MODE=$(VM_EXEC bash -c 'stat -c %a ~/statbus.users.yml ~/statbus.env.credentials | sort -u' | tr -d '\r\n')
[ "$MODE" = 600 ] || { echo "FAIL: kept files mode '$MODE', want 600" >&2; exit 1; }

# The fresh install moves both back in: no second copy in the home, and the
# credentials are reused rather than regenerated.
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG"
VM_EXEC bash -c 'test -f ~/statbus/.users.yml && test -f ~/statbus/.env.credentials &&
    test ! -e ~/statbus.users.yml && test ! -e ~/statbus.env.credentials'
AFTER_SHA=$(VM_EXEC bash -c 'sha256sum ~/statbus/.env.credentials | cut -d" " -f1' | tr -d '\r\n')
[ "$AFTER_SHA" = "$CREDENTIALS_SHA" ] || { echo 'FAIL: reinstall regenerated .env.credentials instead of reusing the kept file' >&2; exit 1; }
assert_health_passes "$VM_NAME"
login_on_vm second-admin-login "$DOMAIN" "$LOGIN_PASSWORD"
VM_EXEC bash -c 'cd ~/statbus && ./sb db status'
echo 'PASS: interactive uninstall moved users and credentials to the home, removed the checkout, and a fresh reinstall moved them back and reused them; the same administrator can sign in'
