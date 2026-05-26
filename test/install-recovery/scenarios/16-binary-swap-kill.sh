#!/bin/bash
# Scenario 16: binary-swap-kill  (C5 / state-bearing Layer 2 kill)
#
# Class:                 killed-by-system-during-binary-swap
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed in the window after replaceBinaryOnDisk
#   completes (new sb binary on disk) but BEFORE updateFlagPostSwap
#   stamps the flag PostSwap leaves the system in an awkward but
#   recoverable state: binary swapped, flag still PreSwap (or
#   initial), migrations NOT applied. The next `./sb install`
#   must detect crashed-upgrade, recoverFromFlag classifies the
#   state (HEAD matches target via the just-completed git
#   checkout; migrations missing per HasPending) and routes through
#   forward-recovery via migrate.Up. End state: row='completed' at
#   the new version, OR row='rolled_back' if forward-recovery
#   itself fails — both are principled terminal states.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2). Populate.
#   2. Snapshot data counts.
#   3. Run first install at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-during-binary-swap.
#      inject.KillHere fires inside executeUpgrade between
#      replaceBinaryOnDisk and updateFlagPostSwap; the install
#      process exits 137. The flag is whatever the prior step
#      stamped (PreSwap from step 2 of executeUpgrade).
#   4. Verify RED: flag file present; binary on disk is the NEW
#      one (HEAD's sb); db.migration max_version unchanged.
#   5. Run a SECOND install (no env vars) for recovery.
#   6. Assert convergence: row in a terminal state (completed OR
#      rolled_back); data intact; flag absent; services healthy.
#
# Hetzner-runnability:
#   READY. The injection site lands with this commit; the
#   recovery paths it exercises (recoverFromFlag's HEAD-matches
#   branch → migrate.Up forward-recovery from Fix 5b, OR
#   rollback via restoreBinary) already exist on master + this
#   branch.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/16-binary-swap-kill.sh \
#     statbus-recovery-16

set -euo pipefail

VM_NAME="${1:-statbus-recovery-16}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 16: binary-swap-kill  (C5 / state-bearing Layer 2)"
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

# Baseline db.migration max version BEFORE the trigger.
BASELINE_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline db.migration max_version: $BASELINE_MAX_VERSION"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — first install with C5 kill injection
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── first install at HEAD with C5 kill injection ──"
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
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=killed-by-system-during-binary-swap \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-c5.sh
upload_sb_to_vm "$VM_NAME"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-c5.sh"
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
echo "── verifying canonical C5 RED state ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after kill" >&2
    exit 1
}
assert_upgrade_row_state "$VM_NAME" "in_progress"
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"
echo "  ✓ RED confirmed: flag present, row in_progress, db.migration unbumped"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — second install for recovery
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery ──"
install_statbus_in_vm "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# Terminal state can be either 'completed' (forward-recovery
# succeeded via migrate.Up) or 'rolled_back' (forward-recovery
# tripped a non-idempotent migration shape and the system fell back
# to rsync-restore). Both are principled. The load-bearing checks
# are: data intact + flag absent + healthy services.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

FINAL_STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    completed)
        echo "  ✓ forward-recovery completed at the new version"
        ;;
    rolled_back)
        echo "  ✓ forward-recovery fell back to rsync-restore (also principled)"
        ;;
    *)
        echo "✗ unexpected terminal state: $FINAL_STATE (expected completed or rolled_back)"
        exit 1
        ;;
esac

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@test.service" 2

echo ""
echo "PASS: binary-swap-kill (recovery reached coherent terminal state, data intact)"
