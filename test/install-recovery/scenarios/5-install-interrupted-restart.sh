#!/usr/bin/env bash
# STATBUS-410: a saved restart intent with no flock holder must be resumed by
# the installer, while a live holder must not be displaced. Uses private mode
# and the released candidate's real first-install path.
set -euo pipefail
VM_NAME="${1:-statbus-recovery-5-install-interrupted-restart}"
HARNESS_DEPLOYMENT_MODE=private
HARNESS_UPGRADE_CHANNEL=stable
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
install_statbus_at_sha "$VM_NAME" "$TARGET_SHA" "$INSTALL_TARGET_TAG"
assert_health_passes "$VM_NAME"
# Model the durable intent left by a SIGKILL immediately after PrepareRestart.
# Stop only the selected profile, with the marker already durable. Nothing is
# deleted by the fixture; the installer owns recovery and marker removal.
VM_SCRIPT_INLINE saved-restart <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/statbus"
cat > tmp/upgrade-in-progress.json <<'FLAG'
{"id":0,"commit_sha":"","started_at":"2026-09-24T12:00:00Z","invoked_by":"operator:restart","trigger":"restart","holder":"install","restart":{"profile":"app","prepared":true,"unit":"statbus-upgrade@statbus.service","daemon":true}}
FLAG
docker compose stop app
REMOTE
RERUN_LOG=$(mktemp)
VM_EXEC bash -c "cd ~ && export STATBUS_ENV_CONFIG=\"\$HOME/install-input.env\" STATBUS_USERS_FILE=/tmp/users.yml STATBUS_INSTALL_VERSION='$INSTALL_TARGET_TAG'; bash /tmp/statbus-install.sh --non-interactive" >"$RERUN_LOG" 2>&1 || { cat "$RERUN_LOG" >&2; exit 1; }
grep -q 'previous restart finished' "$RERUN_LOG" || { cat "$RERUN_LOG" >&2; exit 1; }
VM_EXEC bash -c 'test ! -e ~/statbus/tmp/upgrade-in-progress.json'
assert_health_passes "$VM_NAME"
rm -f "$RERUN_LOG"
echo 'PASS: stale app-only restart restored readiness, cleared intent, and completed the installer'
