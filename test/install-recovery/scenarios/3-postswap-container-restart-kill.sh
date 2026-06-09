#!/bin/bash
# Scenario: 3-postswap-container-restart-kill  (C8 / state-bearing Layer 2 kill)
#
# Class:                 killed-by-system-during-container-restart
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior (one-shot Resuming latch — ROLLBACK, not completion):
#   The C8 kill site (cli/internal/upgrade/service.go:3981) sits between step 11
#   (Start application services: `docker compose up -d --no-build app worker rest`)
#   and step 12 (Verify health) INSIDE applyPostSwap. applyPostSwap's ONLY caller
#   is resumePostSwap (service.go:4353), which stamps the flag Phase=Resuming
#   (service.go:4339) BEFORE invoking it. So every line of applyPostSwap — this
#   kill site included — runs under Phase=Resuming.
#
#   A SINGLE inline `./sb install` reaches Resuming in ONE invocation:
#   executeUpgrade swaps the binary and stamps the flag Phase=PostSwap
#   (service.go:3586), then syscall.Exec's the new binary in-place
#   (service.go:3604). Go opens fds O_CLOEXEC, so the flock is RELEASED across
#   the exec; the re-exec'd `./sb install` finds the flag flock-free
#   (IsFlockHeld=false → install/state.go:172) → StateCrashedUpgrade →
#   RecoverFromFlag → PostSwap branch (service.go:774) → resumePostSwap →
#   Phase=Resuming → applyPostSwap → step 11 → C8 kill. The process exits 137
#   with the flag pinned at Phase=Resuming, the row in_progress, migrations
#   applied.
#
#   The next `./sb install` reads the Resuming flag and hits the one-shot
#   anti-loop LATCH (service.go:755): a death DURING the post-swap resume is
#   NEVER re-resumed — by design it becomes ONE rollback, never a retry. The
#   recovery routes recoverFromFlag → recoveryRollback (service.go:762) →
#   rollback(): restore the snapshot + previous binary + git, bring the OLD
#   (pre-upgrade) version back up, mark the row state='rolled_back' with
#   error containing "UPGRADE_DIED_DURING_RESUME" (ErrResumeDied, const at
#   service.go:1507; set at :762-764; persisted at :4842), clear the flag,
#   and exit 75 (the documented "UPGRADE FAILED, ROLLED BACK" handoff).
#
#   There is NO post-swap window in which a non-planned death re-resumes to
#   step 11+12, so this scenario asserts the LATCH outcome (rolled_back), NOT
#   completion. (Inverse/companion proof: scenario 3-postswap-resume-died-rollback.)
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2). Populate.
#   2. Snapshot data counts (R5 cross-check — the rollback's snapshot
#      restore must return EXACTLY the pre-trigger data; the resume's
#      migrate is undone).
#   3. Run first install at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-during-container-restart.
#      inject.KillHere fires inside applyPostSwap between step 11 and
#      step 12 — already under resumePostSwap's Phase=Resuming stamp;
#      the install process exits 137 with the flag pinned at Phase=Resuming.
#   4. Verify RED state: flag file present, public.upgrade row in
#      state='in_progress', migrations applied (db.migration max
#      version bumped).
#   5. Run a SECOND install (no env vars) for recovery. It reads the
#      Resuming flag → latch → rollback → exits 75 (tolerated).
#   6. Assert the latch outcome: state='rolled_back', error matches
#      UPGRADE_DIED_DURING_RESUME, flag absent, no orphan backup, data
#      restored intact from the snapshot, services healthy at the
#      rolled-back (pre-upgrade) version.
#
# Hetzner-runnability:
#   READY. The injection site and the latch path it exercises
#   (recoverFromFlag Resuming branch → recoveryRollback → rollback) both
#   exist on master + this branch. Validated on CI.
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
echo "  ✓ RED confirmed: flag (pinned Phase=Resuming) + row in_progress (migrations applied; containers indeterminate)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — second install for recovery
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery ──"
# The recovery reads the Resuming flag → the one-shot latch (service.go:755) →
# recoveryRollback → rollback() → os.Exit(75) (service.go:4882), the documented
# "UPGRADE FAILED, ROLLED BACK" handoff. install_statbus_in_vm returns that exit
# code, so the wrapper propagates 75. That IS the scenario-expected outcome here
# (the death-during-resume MUST roll back, never re-resume to completion); the
# Phase 6 assertions verify the post-rollback state. Tolerate exit 75 specifically;
# any other non-zero is a real recovery failure and aborts. Exit 0 would mean the
# recovery wrongly reached 'completed' (the OLD, pre-latch contract) — that is NOT
# tolerated here and is caught loudly by the row-state assertion below.
install_statbus_in_vm "$VM_NAME" || { rc=$?; [ "$rc" -eq 75 ] || exit "$rc"; }

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── latch-outcome convergence checks (ROLLBACK, not completion) ──"

# Fail loudly and specifically if the recovery wrongly reached 'completed' — that
# is the OLD pre-latch contract (re-run step 11+12 to completion), which the
# Resuming one-shot latch (service.go:755) deliberately does NOT produce. A
# death during the post-swap resume becomes ONE rollback, never a re-resume.
FINAL_STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  final upgrade row state: $FINAL_STATE"
if [ "$FINAL_STATE" = "completed" ]; then
    echo "✗ row state='completed' — the death-during-resume was NOT supposed to re-resume to step 11+12." >&2
    echo "  The Resuming one-shot latch (service.go:755) must roll back, not complete. Either the latch" >&2
    echo "  regressed, or the kill did not fire under Phase=Resuming." >&2
    exit 1
fi

# The expected terminal: rolled_back. The snapshot restore succeeds → healthy at
# the old version. (A degraded 'failed' would mean the rollback's OWN restore
# also failed — a separate, real failure; assert the principled rolled_back here.)
assert_upgrade_row_state "$VM_NAME" "rolled_back"

# The error column is the unattended operator's diagnostic surface — it must name
# the latch code so support knows this was a death-during-resume, not a clean
# step failure (ErrResumeDied, service.go:1507).
assert_upgrade_row_error_matches "$VM_NAME" "UPGRADE_DIED_DURING_RESUME"

# Data restored intact from the snapshot — the resume's migrate was undone by
# rollback()'s restoreDatabase.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# The flag is gone — the mutex is released so a subsequent ./sb install is not
# wedged at StateLiveUpgrade / does not re-enter recovery.
assert_flag_file_absent "$VM_NAME"

# No LEGACY orphan backups accumulated (managed pre-upgrade-active/syncing are
# excluded; the rollback restores FROM the finalized active snapshot, which may
# legitimately persist — it is not an orphan).
assert_no_orphan_backup "$VM_NAME"

# Services healthy at the rolled-back (pre-upgrade) version.
assert_health_passes "$VM_NAME"

# One rollback, not a restart loop: the systemd upgrade unit must not be churning.
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 3-postswap-container-restart-kill (death during the post-swap resume became ONE rollback via the Resuming latch: row rolled_back with UPGRADE_DIED_DURING_RESUME, snapshot restored, flag cleared, services healthy at the pre-upgrade version)"
