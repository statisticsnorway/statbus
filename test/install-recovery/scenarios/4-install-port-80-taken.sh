#!/usr/bin/env bash
# STATBUS-385: Apache owns port 80 before the candidate's first install.
# Requires a tagged candidate. The host's public IP is used with sslip.io so
# a standalone rerun can request a real public certificate, if ingress allows.
set -euo pipefail
VM_NAME="${1:-statbus-recovery-4-install-port-80-taken}"
HARNESS_DEPLOYMENT_MODE=standalone
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
# This address has a public A record, unlike the harness's private-mode name.
HARNESS_SITE_DOMAIN="${VM_IP//./-}.sslip.io"
VM_ROOT_EXEC bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 >/dev/null && systemctl enable --now apache2'
# No sudoers fixture: the application user must discover Apache via systemd.
VM_ROOT_EXEC bash -c 'ss -ltn "( sport = :80 )" | grep -q LISTEN'
FIRST_LOG=$(mktemp)
if install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG" >"$FIRST_LOG" 2>&1; then
    cat "$FIRST_LOG" >&2
    echo 'port-80 conflict unexpectedly passed' >&2
    exit 1
fi
grep -q 'sudo systemctl disable --now apache2' "$FIRST_LOG" || { cat "$FIRST_LOG" >&2; exit 1; }
grep -q 'curl -fsSL https://statbus.org/install.sh | bash' "$FIRST_LOG" || { cat "$FIRST_LOG" >&2; exit 1; }
grep -qi 'answers are saved' "$FIRST_LOG" || { cat "$FIRST_LOG" >&2; exit 1; }
[ "$(VM_EXEC bash -c 'cd ~/statbus && docker compose ps -q | wc -l' | tr -d ' ')" = 0 ] || { echo 'StatBus services started before port preflight' >&2; exit 1; }
VM_ROOT_EXEC systemctl disable --now apache2
# Paste the exact command emitted in the refusal, including release and answer paths.
RERUN_COMMAND=$(grep '^port 80 is in use by ' "$FIRST_LOG" | tail -1 | sed 's/^.*Then run the same install command again: //')
[[ "$RERUN_COMMAND" == *'curl -fsSL https://statbus.org/install.sh | env '* && "$RERUN_COMMAND" == *"STATBUS_INSTALL_VERSION=$INSTALL_TARGET_TAG"* && "$RERUN_COMMAND" == *'bash -s -- --non-interactive'* ]] || { cat "$FIRST_LOG" >&2; exit 1; }
VM_EXEC bash -c "cd ~ && $RERUN_COMMAND"
assert_health_passes "$VM_NAME"
rm -f "$FIRST_LOG"
echo 'PASS: Apache port conflict refused before service start and saved-answer rerun is healthy'
