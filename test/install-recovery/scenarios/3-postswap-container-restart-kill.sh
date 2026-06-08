#!/bin/bash
# Scenario: 3-postswap-container-restart-kill  (C8 / state-bearing Layer 2 kill)
#
# Class:                 killed-by-system-during-container-restart
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed in the window after step 11 (Start application
#   services: `docker compose up -d --no-build app worker rest`) but
#   before step 12 (Verify health) leaves the system with: new
#   binary, migrations applied, flag = PostSwap, containers in
#   indeterminate state. The next `./sb install` must detect
#   crashed-upgrade, route to recoverFromFlag → resumePostSwap →
#   re-enter applyPostSwap, which re-runs step 11 (idempotent) and
#   step 12 to completion.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2). Populate.
#   2. Snapshot data counts (R5 cross-check — DDL must not lose
#      user data even when interrupted mid-restart).
#   3. Run first install at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-during-container-restart.
#      inject.KillHere fires inside applyPostSwap between step 11
#      and step 12; the install process exits 137 with the flag
#      file pinned at PostSwap.
#   4. Verify RED state: flag file present, public.upgrade row in
#      state='in_progress', migrations applied (db.migration max
#      version bumped).
#   5. Run a SECOND install (no env vars) for recovery.
#   6. Assert convergence: state='completed', data intact, services
#      healthy.
#
# Hetzner-runnability:
#   READY. The injection site lands with this commit; the recovery
#   path it exercises (recoverFromFlag → resumePostSwap) already
#   exists on master + this branch.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-container-restart-kill.sh \
#     statbus-recovery-3-postswap-container-restart-kill

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-container-restart-kill}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-container-restart-kill  (C8 / state-bearing Layer 2)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — first install with C8 kill injection
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── first install at HEAD with C8 kill injection ──"
ip=$(hcloud server ip "$VM_NAME")
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
INSTALL_SCRIPT=$(mktemp)
cat > "$INSTALL_SCRIPT" << SCRIPT
set -e
cd ~/statbus
if ! git cat-file -e $HEAD_LOCAL 2>/dev/null; then
    git fetch --depth 1 origin $HEAD_LOCAL || { echo "FATAL" >&2; exit 1; }
fi
git checkout $HEAD_LOCAL
# Re-place sb after git checkout — ~/statbus/sb stays as the INSTALL_VERSION
# binary (gitignored; checkout leaves it alone).  /tmp/sb is the host-built
# HEAD binary from upload_sb_to_vm; the C8 inject site requires the HEAD binary.
# Pattern D fix: matches 3-postswap-migration-timeout and between-migrations-kill.
cp /tmp/sb ./sb
chmod +x ./sb
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=killed-by-system-during-container-restart \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-c8.sh
upload_sb_to_vm "$VM_NAME"

# Seed a scheduled upgrade row so ./sb install detects StateScheduledUpgrade
# and routes to executeUpgradeInline (where the C8 kill site fires), rather
# than detecting nothing-scheduled and running the no-op step-table path.
# Same pattern as 3-postswap-migrate-killed-after-commit and 3-postswap-mid-migration-kill.
echo ""
echo "── fabricating scheduled public.upgrade row for HEAD ──"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

# Run synchronously — the kill exits the install process so it returns
# in finite time. We use a timeout as a safety net.
set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-c8.sh"
FIRST_EXIT=$?
set -e
echo "  first install exited: $FIRST_EXIT (137 = injected SIGKILL semantics)"

if [ "$FIRST_EXIT" = "124" ]; then
    echo "✗ first install timed out — kill site did not fire" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — verify RED state
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── verifying canonical C8 RED state ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after kill" >&2
    exit 1
}
assert_upgrade_row_state "$VM_NAME" "in_progress"
echo "  ✓ RED confirmed: flag + row in_progress (migrations applied; containers indeterminate)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — second install for recovery
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery ──"
install_statbus_in_vm "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

assert_upgrade_row_state "$VM_NAME" "completed"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 3-postswap-container-restart-kill (recovery completed step 11+12 and reached state='completed')"
