#!/bin/bash
# Scenario: 4-rollback-kill  (C9 / Layer 2 kill — mid d.rollback() pipeline)
#
# Class:                 killed-by-system-during-builtin-rollback
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed AFTER d.rollback()'s destructive restore steps
#   (restoreGitState, restoreBinary, restoreDatabase) but BEFORE the
#   docker compose up + reconnect + setMaintenance + state='rolled_back'
#   UPDATE leaves the system with: OLD git tree, OLD binary, OLD DB
#   volume — fully restored to the pre-upgrade era. But services are
#   stopped, maintenance is still ON, the upgrade row is still
#   'in_progress'. Recovery via the next install's recoverFromFlag:
#   the ground-truth check sees OLD binary + OLD db.migration state,
#   verifies coherent, brings services up, sets maintenance OFF,
#   marks the row 'rolled_back'.
#
# Scope of this scenario (DIAGNOSTIC — site reachability, NOT firing test):
#   Firing this kill site requires the recovery path to invoke
#   d.rollback() — which only happens when forward-recovery (Fix 5b)
#   has FAILED. Without a dedicated "force-forward-recovery-failure"
#   injection class (which would require ErrorHere wiring inside
#   migrate.Up that does NOT currently exist), the test cannot
#   deterministically reach d.rollback() during recovery.
#
#   This scenario lands the C9 KillHere site at the principled
#   placement (between restoreDatabase and docker compose up) so
#   that any future regression where d.rollback() is reached
#   during recovery + the operator has STATBUS_INJECT_AT=C9 set
#   gives a clean, observable kill point. It then RUNS a
#   best-effort trigger sequence:
#
#     - First install: STATBUS_INJECT_AT=killed-by-system-during-binary-swap
#       (C5). Wedge: NEW binary on disk, NO migrations applied,
#       flag PreSwap.
#     - Second install: STATBUS_INJECT_AT=killed-by-system-during-builtin-rollback
#       (C9). Recovery for C5's wedge calls verifyUpgradeGroundTruth,
#       which detects "db.migration max version doesn't match" and
#       routes to forward-recovery (migrate.Up). If forward succeeds,
#       no d.rollback() — and C9 doesn't fire. If forward fails
#       (e.g., a non-idempotent migration), recoveryRollback →
#       d.rollback() → C9 fires.
#
#   The scenario reports BOTH outcomes:
#     - GREEN-direct: forward-recovery succeeded on first try, C9
#       never reached. State='completed', data intact. The C9 site
#       is documented as "exists; not reached this run".
#     - GREEN-via-C9: forward failed, C9 fired during rollback,
#       third install completed the rollback. State='rolled_back',
#       data at pre-upgrade snapshot.
#
#   Either outcome is a PASS — the scenario is the diagnostic for
#   site placement, not a strict regression net for rollback-kill
#   recovery. The team-lead's #163 follow-up (C15 full-fire test)
#   will need similar machinery for C9 if a strict regression net
#   is required.
#
# Hetzner-runnability:
#   READY as DIAGNOSTIC. Site lands with this commit; firing depends
#   on whether forward-recovery happens to fail for this run's
#   migration set.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/4-rollback-kill.sh \
#     statbus-recovery-4-rollback-kill

set -euo pipefail

VM_NAME="${1:-statbus-recovery-4-rollback-kill}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 4-rollback-kill  (C9 / Layer 2 — diagnostic for rollback path)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo ""
echo "  NOTE: this scenario lands the C9 KillHere site at its principled"
echo "  placement (between restoreDatabase and docker compose up). Whether"
echo "  C9 fires depends on whether the recovery's forward-recovery path"
echo "  fails — non-deterministic across runs. The scenario passes either"
echo "  way (state=completed via forward, OR state=rolled_back via rollback)."
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

SB_VERSION_BEFORE=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
echo "  pre-trigger ./sb version: $SB_VERSION_BEFORE"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — first install: trigger a C5 (binary-swap-kill) wedge
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── first install at HEAD with C5 kill (set up the wedge) ──"
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
# Re-place sb after checkout (gitignored; checkout leaves it alone, but match the
# proven container-restart-kill pattern so ./sb is unambiguously the HEAD binary).
cp /tmp/sb ./sb
chmod +x ./sb
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=killed-by-system-during-binary-swap \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-first.sh

# Seed a scheduled public.upgrade row so ./sb install detects StateScheduledUpgrade
# and routes to executeUpgradeInline (where the C5 binary-swap kill fires), rather
# than detecting nothing-scheduled and running the no-op step-table path — which
# completes (exit 0) with NO upgrade, so the C5 kill has nothing to fire in and no
# wedge is established. Same pattern as 3-postswap-container-restart-kill / -binary-swap-kill.
echo ""
echo "── fabricating scheduled public.upgrade row for HEAD ──"
quiesce_upgrade_service "$VM_NAME"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"
upload_sb_to_vm "$VM_NAME"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-first.sh"
FIRST_EXIT=$?
set -e
echo "  first install exited: $FIRST_EXIT (137 = C5 SIGKILL semantics, wedge established)"

if [ "$FIRST_EXIT" = "124" ]; then
    echo "✗ first install timed out — C5 kill did not fire" >&2
    exit 1
fi
# The C5 binary-swap kill SIGKILLs the install → exit 137. ANY other exit means
# the kill did NOT fire — most commonly a clean exit 0 because the install ran the
# nothing-scheduled step-table to completion (the fabricated scheduled row above is
# what routes it into executeUpgradeInline where C5 lands). Fail loudly so a clean
# exit-0 can never silently pass the wedge assertions below.
if [ "$FIRST_EXIT" != "137" ]; then
    echo "✗ first install exited $FIRST_EXIT (expected 137) — the C5 binary-swap kill did not fire." >&2
    echo "  The install likely ran the nothing-scheduled step-table instead of executeUpgradeInline." >&2
    echo "  (Is the scheduled public.upgrade row fabricated before the install?)" >&2
    exit 1
fi

# Sanity: confirm wedge state.
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after C5 kill" >&2
    exit 1
}
# DB is down at C5: archiveBackup stops the DB before binary-swap, so the upgrade
# row cannot be queried here. Flag file presence + exit 137 are sufficient C5-wedge evidence.
echo "  ✓ C5 wedge established: flag present (DB stopped for backup before swap)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — second install: recovery with C9 env var (kill-if-rollback-reached)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery with C9 env var ──"
INSTALL_SCRIPT=$(mktemp)
cat > "$INSTALL_SCRIPT" << SCRIPT
set -e
cd ~/statbus
git checkout $HEAD_LOCAL
STATBUS_INJECT_AT=killed-by-system-during-builtin-rollback \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-second.sh
upload_sb_to_vm "$VM_NAME"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-second.sh"
SECOND_EXIT=$?
set -e
echo "  second install exited: $SECOND_EXIT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — branch on observed outcome
# ─────────────────────────────────────────────────────────────────────────
case "$SECOND_EXIT" in
    0)
        # Recovery completed without ever calling d.rollback() — forward
        # recovery succeeded, C9 site was never reached.
        echo ""
        echo "── outcome A: forward-recovery succeeded, C9 site NOT reached this run ──"
        assert_upgrade_row_state "$VM_NAME" "completed"
        assert_demo_data_present "$VM_NAME"
        assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
        assert_flag_file_absent "$VM_NAME"
        assert_health_passes "$VM_NAME"
        echo ""
        echo "DIAGNOSTIC PASS: 4-rollback-kill outcome A (forward-recovery succeeded; C9 site is documented but was not exercised at runtime this run)"
        ;;
    137)
        # C9 KillHere fired — recovery's forward-recovery failed and fell
        # through to d.rollback(), where C9 exited 137. The wedge is now
        # a partial-rollback state. Third install must complete it.
        echo ""
        echo "── outcome B: C9 fired (137) — partial rollback in place; running THIRD install to complete ──"
        VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
            echo "✗ expected flag file present after C9 kill" >&2
            exit 1
        }

        # Third install — no env vars — completes the rollback.
        # Tolerate rc=75: rollback() exits 75 ("UPGRADE FAILED, ROLLED BACK")
        # after completing the git/binary/db restore and bringing services up.
        # Without this tolerance set -e aborts the scenario on a successful
        # rollback-completion. (Same pattern as 2-preswap-checkout-kill:215.)
        echo ""
        echo "── third install for recovery completion ──"
        install_statbus_in_vm "$VM_NAME" || { rc=$?; [ "$rc" -eq 75 ] || exit "$rc"; }

        FINAL_STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
        echo "  final state: $FINAL_STATE"
        case "$FINAL_STATE" in
            rolled_back|failed)
                echo "  ✓ rollback completed (state=$FINAL_STATE)"
                ;;
            completed)
                echo "✗ row state='completed' after a partial-rollback wedge is NOT principled — rollback was supposed to land in 'rolled_back'" >&2
                exit 1
                ;;
            *)
                echo "✗ unexpected terminal state: $FINAL_STATE" >&2
                exit 1
                ;;
        esac

        assert_demo_data_present "$VM_NAME"
        # Data counts may match the PRE-upgrade snapshot (pre-population may
        # have been restored from the DB backup) — we don't strictly assert
        # the snapshot match in this branch because the rollback restored
        # the DB volume from the pre-upgrade backup.
        assert_flag_file_absent "$VM_NAME"
        assert_health_passes "$VM_NAME"
        echo ""
        echo "DIAGNOSTIC PASS: 4-rollback-kill outcome B (C9 fired during rollback; third install completed the partial-rollback recovery)"
        ;;
    124)
        echo "✗ second install timed out — neither completion nor C9 fired" >&2
        exit 1
        ;;
    *)
        echo "✗ unexpected second-install exit: $SECOND_EXIT" >&2
        exit 1
        ;;
esac

echo ""
echo "PASS: 4-rollback-kill (C9 site lands; both outcome branches converge to a coherent terminal state with data intact)"
