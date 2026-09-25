#!/usr/bin/env bash
# STATBUS-410: a live restart mutex must block competing installer recovery.
# Reuses the installed tagged candidate fixture, never runs an actual upgrade.
set -euo pipefail
VM_NAME="${1:-statbus-recovery-5-install-live-upgrade-wait}"
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
VM_SCRIPT_INLINE live-restart-holder <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/statbus"
cat > tmp/upgrade-in-progress.json <<'FLAG'
{"id":0,"commit_sha":"","started_at":"2026-09-24T12:00:00Z","invoked_by":"operator:restart","trigger":"restart","holder":"install","restart":{"profile":"app","prepared":true,"daemon":false}}
FLAG
# An app-only restart never stops the upgrade unit (service_restart.go), so
# it cannot carry Daemon=true without a unit to restart. That invalid fixture
# made the post-holder retry fail at systemctl start "" and retain its marker.
# -F makes flock exec sleep instead of leaving a child holding the lock after
# the recorded flock PID is killed. The retry below must see the lock released.
nohup flock -F -x tmp/upgrade-in-progress.json sleep 90 > tmp/live-restart-holder.log 2>&1 </dev/null &
echo $! > tmp/test-live-restart-pid
sleep 1
kill -0 "$(cat tmp/test-live-restart-pid)"
REMOTE
harness_register_log live-restart-holder /home/statbus/statbus/tmp/live-restart-holder.log "$VM_IP"
BEFORE=$(VM_EXEC bash -c 'cd ~/statbus && sha256sum tmp/upgrade-in-progress.json | cut -d" " -f1')
REFUSAL=$(mktemp)
if VM_EXEC bash -c "cd ~ && export STATBUS_ENV_CONFIG=\"\$HOME/install-input.env\" STATBUS_USERS_FILE=/tmp/users.yml STATBUS_INSTALL_VERSION='$INSTALL_TARGET_TAG'; bash /tmp/statbus-install.sh --non-interactive" >"$REFUSAL" 2>&1; then
    cat "$REFUSAL" >&2
    echo 'live restart was not refused' >&2
    exit 1
fi
grep -Eqi 'restart is still running|wait for it to finish' "$REFUSAL" || { cat "$REFUSAL" >&2; exit 1; }
AFTER=$(VM_EXEC bash -c 'cd ~/statbus && sha256sum tmp/upgrade-in-progress.json | cut -d" " -f1')
[ "$BEFORE" = "$AFTER" ] || { echo 'live restart intent was modified' >&2; exit 1; }
VM_EXEC bash -c 'cd ~/statbus && kill "$(cat tmp/test-live-restart-pid)" && flock -w 10 tmp/upgrade-in-progress.json true'
VM_EXEC bash -c 'cd ~/statbus && ! grep -q "\"pid\"" tmp/upgrade-in-progress.json'
VM_EXEC bash -c "cd ~ && export STATBUS_ENV_CONFIG=\"\$HOME/install-input.env\" STATBUS_USERS_FILE=/tmp/users.yml STATBUS_INSTALL_VERSION='$INSTALL_TARGET_TAG'; bash /tmp/statbus-install.sh --non-interactive"
assert_health_passes "$VM_NAME"
rm -f "$REFUSAL"
echo 'PASS: live restart refused without competing recovery, then converged after holder exited'
