#!/bin/bash
# Scenario: 2-preswap-binary-swap-kill  (C5 / state-bearing Layer 2 kill)
#
# Class:                 killed-by-system-during-binary-swap
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior (PreSwap kill → ROLLBACK, never forward-recovery):
#   The C5 kill fires after replaceBinaryOnDisk completes (new sb binary on
#   disk) but BEFORE updateFlagPostSwap stamps the flag PostSwap
#   (service.go:3586). The COMMIT BOUNDARY is that stamp, not the physical
#   binary swap — so at the kill the flag is still Phase=PreSwap, migrations
#   NOT applied. The next `./sb install` detects crashed-upgrade and routes to
#   recoverFromFlag, which dispatches purely by flag phase:
#     install-clear (:739) → Resuming (:755) → PostSwap (:774) → PreSwap (:822).
#   A PreSwap flag hits the :822 branch, which UNCONDITIONALLY rolls back
#   (recoveryRollback → rollback) and returns BEFORE the service-held reconcile
#   at :846 — so the migrate.Up forward-recovery there is UNREACHABLE for any
#   PreSwap flag. rollback() reverts git to the previous version, restores the
#   binary (./sb.old → ./sb), restores the snapshot, and marks the row
#   state='rolled_back' with error "INSTALL_PRECONDITION_FAILED: upgrade killed
#   in PreSwap phase before binary-swap commit boundary", then exits 75.
#
#   So the principled terminals here are rolled_back (expected-clean) or failed
#   (degraded — the rollback's own restore tripped); NEVER completed. (The
#   earlier premise — "HEAD matches target → forward-recover via migrate.Up →
#   completed" — predates the :822 PreSwap guard, added per the
#   2-preswap-backup-kill RED proof, run 26607271739; the guard exists precisely
#   to STOP a PreSwap kill from self-healing to completed. 'completed' here would
#   mean the guard regressed and is asserted-against, not accepted.)
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2). Populate.
#   2. Snapshot data counts + baseline db.migration max version.
#   3. Run first install at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-during-binary-swap.
#      inject.KillHere fires inside executeUpgrade between
#      replaceBinaryOnDisk and updateFlagPostSwap; the install
#      process exits 137 with the flag still Phase=PreSwap.
#   4. Verify RED: flag file present. (Row-state + migration checks are
#      DEFERRED to Phase 6 — the DB is stopped for the consistent backup,
#      upstream of C5, and not restarted until post-swap.)
#   5. Run a SECOND install (no env vars) for recovery → rolls back, exits 75
#      (tolerated).
#   6. Assert convergence: row state in {rolled_back, failed} (completed → fail
#      loudly), error matches INSTALL_PRECONDITION_FAILED, db.migration unchanged
#      from baseline, data intact, flag absent, services healthy.
#
# Hetzner-runnability:
#   READY. The injection site and the recovery path it exercises
#   (recoverFromFlag :822 PreSwap branch → recoveryRollback → rollback via
#   restoreBinary/restoreGitState/restoreDatabase) both exist on master + this
#   branch.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/2-preswap-binary-swap-kill.sh \
#     statbus-recovery-2-preswap-binary-swap-kill

set -euo pipefail

VM_NAME="${1:-statbus-recovery-2-preswap-binary-swap-kill}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 2-preswap-binary-swap-kill  (C5 / state-bearing Layer 2)"
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
# NOTE: do NOT assert public.upgrade.state or db.migration here — executeUpgrade
# stopped the DB container for the consistent backup (service.go:3462 "Stop
# database for consistent backup") UPSTREAM of the C5 binary-swap kill, and it
# is NOT restarted until applyPostSwap (post-swap). So any `./sb psql`-backed
# assertion (assert_upgrade_row_state / assert_db_migration_max_version_unchanged)
# fails with "connection refused" → `return 1` under `set -e` → silent script
# exit. The flag-file `ls` above proves the upgrade was in-flight when killed
# (the flag carries Phase=PreSwap). The row-state + migration-unchanged checks
# are deferred to Phase 6, after the recovery install restarts the DB. (Mirror
# of 2-preswap-backup-kill's DB-down deferral.)
echo "  ✓ RED confirmed: flag present (Phase=PreSwap); DB down for the consistent backup — row/migration checks deferred to Phase 6"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — second install for recovery
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery ──"
# The recovery reads the PreSwap flag → recoverFromFlag PreSwap branch
# (service.go:822) → recoveryRollback → rollback() → os.Exit(75), the documented
# "UPGRADE FAILED, ROLLED BACK" handoff. install_statbus_in_vm propagates that
# exit code, so tolerate 75 specifically; any other non-zero is a real recovery
# failure and aborts. Exit 0 would mean the recovery wrongly reached 'completed'
# (forward-recovery, which the :822 guard makes unreachable) — caught loudly by
# the row-state guard below. (Mirror of 2-preswap-backup-kill:223.)
install_statbus_in_vm "$VM_NAME" || { rc=$?; [ "$rc" -eq 75 ] || exit "$rc"; }

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions (PreSwap kill → rolled_back | failed, NEVER completed)
#
# A PreSwap flag hits recoverFromFlag's :822 branch, which rolls back
# unconditionally and returns BEFORE the :846 forward-recovery — so 'completed'
# is UNREACHABLE here. The principled terminals are rolled_back (clean) or failed
# (degraded restore); 'completed' is asserted-against (would mean the :822 guard
# regressed). DB-down checks deferred from Phase 4 (row-state, migration-unchanged)
# run here, where the recovery install has restarted the DB.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

# Fail loudly and specifically if the recovery wrongly reached 'completed' —
# the :822 PreSwap guard (service.go) deliberately rolls back instead of
# forward-recovering, so a PreSwap kill can never self-heal to completed.
FINAL_STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  final upgrade row state: $FINAL_STATE"
if [ "$FINAL_STATE" = "completed" ]; then
    echo "✗ row state='completed' — a PreSwap kill must NOT forward-recover. The :822" >&2
    echo "  PreSwap guard rolls back before the :846 forward-recovery branch; 'completed'" >&2
    echo "  here means that guard regressed (or the kill fired past the PostSwap stamp)." >&2
    exit 1
fi

# Principled ABORT terminal: rolled_back (expected-clean — restoreGitState reverts
# git, restoreBinary restores ./sb.old → ./sb, restoreDatabase restores the
# snapshot → healthy at the old version) OR failed (degraded-but-terminal — the
# :822 guard still fired, but the rollback's OWN restore tripped and the box needs
# manual recovery). Both are valid PreSwap-abort terminals; completed is not
# (guarded above). Unified with backup-kill + checkout-kill. NOTE: kept permissive
# pending EMPIRICAL proof that a fresh VM reaches clean rolled_back reliably — once
# the first fixed run confirms that, this can tighten to rolled_back-only.
case "$FINAL_STATE" in
    rolled_back)
        echo "  ✓ rolled back to the previous version (clean PreSwap-guard rollback)"
        ;;
    failed)
        echo "  ⚠ terminal 'failed' (degraded tier — the :822 guard fired but the rollback's own restore failed); investigate restoreGitState/restoreDatabase"
        ;;
    *)
        echo "✗ unexpected terminal state: $FINAL_STATE (expected rolled_back or failed)" >&2
        exit 1
        ;;
esac

# The error column must name the PreSwap-guard rollback reason — proves this was
# the recoverFromFlag :822 PreSwap rollback (ErrInstallPreconditionFailed =
# "INSTALL_PRECONDITION_FAILED", service.go:1501), carried in the error prefix on
# both the rolled_back and failed tiers above.
assert_upgrade_row_error_matches "$VM_NAME" "INSTALL_PRECONDITION_FAILED"

# Deferred from Phase 4 (DB now up): migrations were never applied (migrate runs
# post-swap, never reached) and the rollback restored the pre-upgrade snapshot —
# so db.migration max is unchanged from baseline.
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 2-preswap-binary-swap-kill (PreSwap kill → :822 guard aborted the upgrade; row $FINAL_STATE with INSTALL_PRECONDITION_FAILED, migrations unchanged from baseline, data intact)"
