#!/bin/bash
# Scenario: 2-preswap-checkout-kill  (C4 / Layer 2 kill — preswap git checkout)
#
# Class:                 killed-by-system-during-preswap-checkout
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed in executeUpgrade AFTER the git checkout to the
#   target commit completes but BEFORE the binary swap leaves the
#   system with: working tree at the NEW commit, backup .tmp dir
#   already finalized (rename happened upstream of the kill), OLD
#   binary on disk, flag PreSwap, no PostSwap stamp. Recovery via
#   the next install's recoverFromFlag → PreSwap branch:
#   restoreGitState reverts the working tree to the previous
#   version via the `pre-upgrade` branch pinned upstream
#   (executeUpgrade pins it BEFORE the destructive phases — see
#   service.go around the `git branch -f pre-upgrade HEAD` line),
#   discards the backup, clears the flag, marks the upgrade row
#   'failed' or 'rolled_back'. Convergence: working tree back at
#   the OLD commit, OLD binary live, data intact.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2).
#   2. Populate via populate_with_demo_data.
#   3. Snapshot data counts.
#   4. Snapshot HEAD commit on the VM (post-bootstrap; this is the
#      OLD commit that restoreGitState must return us to).
#   5. Run first install at HEAD-local with
#      STATBUS_INJECT_AT=killed-by-system-during-preswap-checkout.
#      inject.KillHere fires in executeUpgrade right after git
#      checkout commitSHA succeeds; install exits 137 with: flag
#      present, backup dir finalized (the rename happened in the
#      backup phase which ran upstream), working tree at HEAD-local,
#      ./sb binary still OLD.
#   6. Verify RED: flag file present; upgrade row='in_progress';
#      working tree at HEAD-local commit (git rev-parse HEAD);
#      ./sb binary still the OLD version.
#   7. Run a SECOND install (no env vars) for recovery.
#   8. Assert convergence: row state='failed' or 'rolled_back';
#      working tree BACK at the OLD commit (the pre-upgrade branch
#      target); data intact; flag absent; backup dir cleaned up;
#      ./sb still OLD.
#
# Hetzner-runnability:
#   READY. Injection site lands with this commit. PreSwap branch's
#   restoreGitState already exists and is the canonical recovery
#   path for "checkout advanced, no binary swap yet".
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/2-preswap-checkout-kill.sh \
#     statbus-recovery-2-preswap-checkout-kill

set -euo pipefail

VM_NAME="${1:-statbus-recovery-2-preswap-checkout-kill}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 2-preswap-checkout-kill  (C4 / Layer 2 kill — git-checkout phase)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD-local: $HEAD_LOCAL ($(echo "$HEAD_LOCAL" | cut -c1-8))"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# Snapshot the working-tree commit AFTER the initial install — this is the
# "OLD" commit that restoreGitState must return us to. We don't assume the
# install put us at the INSTALL_VERSION's tag exactly; we read what's there.
OLD_COMMIT=$(VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d '\r' || echo "")
if [ -z "$OLD_COMMIT" ]; then
    echo "✗ could not read working-tree HEAD post-initial-install" >&2
    exit 1
fi
echo "  pre-trigger working-tree HEAD: $OLD_COMMIT ($(echo "$OLD_COMMIT" | cut -c1-8))"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — first install at HEAD with C4 kill injection
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── first install at HEAD with C4 kill injection ──"
ip=$(hcloud server ip "$VM_NAME")
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
STATBUS_INJECT_AT=killed-by-system-during-preswap-checkout \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-c4.sh
upload_sb_to_vm "$VM_NAME"

# Baseline ./sb version AFTER harness upload — upload_sb_to_vm replaces the
# INSTALL_VERSION binary with the HEAD-SHA binary.  The C4 kill fires inside
# executeUpgrade's preswap-checkout phase, BEFORE the upgrade's own binary-
# swap step, so the on-disk binary should be unchanged across RED and GREEN.
# Capturing BEFORE upload_sb_to_vm gave the INSTALL_VERSION string while the
# binary on disk was already the HEAD-SHA binary → assertion mismatch.
SB_VERSION_BEFORE=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
echo "  staged ./sb version (HEAD-SHA binary, pre-trigger): $SB_VERSION_BEFORE"

# Seed a scheduled public.upgrade row at HEAD so the install state detector
# classifies as StateScheduledUpgrade (and dispatches executeUpgrade → the
# C4 kill site inside the preswap-checkout phase). Without this, RUN 1 sees
# nothing-scheduled (current==target: both derive from the running binary's
# ldflags version, which is HEAD after upload_sb_to_vm overwrote the
# v2026.05.2 binary) → idempotent step-table refresh → exits 0 → KillHere
# never fires. Mirror of 2-preswap-backup-kill:135–141.
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

# IMPORTANT for C4: the install script above does `git checkout $HEAD_LOCAL`
# BEFORE invoking ./sb install. That's the harness's setup checkout (to
# get HEAD's code + inject site on disk), NOT the executeUpgrade git
# checkout that C4 targets. Inside ./sb install → executeUpgrade, the
# `git fetch + git checkout` step targets `commitSHA` (= HEAD's full SHA
# in this scenario, same as $HEAD_LOCAL), and the C4 KillHere fires
# right after that internal checkout — so when the kill fires, the
# working tree is at HEAD-local, just as the wedge spec describes.
# The setup checkout above and the executeUpgrade checkout converge on
# the same SHA, but they are conceptually distinct phases.

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-c4.sh"
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
echo "── verifying canonical C4 RED state ──"

VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after kill" >&2
    exit 1
}
# NOTE: do NOT assert public.upgrade.state='in_progress' here — executeUpgrade
# stopped the DB container for the consistent backup (service.go:3462 "Stop
# database for consistent backup") UPSTREAM of the C4 checkout kill, and it is
# NOT restarted until applyPostSwap (post-swap). So `./sb psql` would fail with
# "connection refused" and assert_upgrade_row_state would `return 1` under
# `set -e` → silent script exit before any post-kill assertion. The flag-file
# `ls` above already proves the upgrade was in-flight when killed (the flag
# carries Phase=PreSwap); the working-tree + binary checks below are the
# C4-specific RED proof and need NO DB. The row-state convergence check belongs
# in Phase 6, after the recovery install restarts the DB. (Mirror of
# 2-preswap-backup-kill's DB-down deferral.)

# Working tree at HEAD-local (C4 fires right after the executeUpgrade
# checkout).
WT_COMMIT_DURING=$(VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d '\r' || echo "")
if [ "$WT_COMMIT_DURING" != "$HEAD_LOCAL" ]; then
    echo "✗ working tree not at HEAD-local during RED ($WT_COMMIT_DURING vs $HEAD_LOCAL)" >&2
    echo "  Kill may have fired before the executeUpgrade checkout — investigate site placement." >&2
    exit 1
fi
echo "  ✓ working tree at HEAD-local ($(echo "$HEAD_LOCAL" | cut -c1-8))"

# ./sb binary still OLD (binary swap is downstream of C4).
SB_VERSION_DURING=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
if [ "$SB_VERSION_DURING" != "$SB_VERSION_BEFORE" ]; then
    echo "✗ ./sb binary changed during preswap-checkout phase ($SB_VERSION_BEFORE → $SB_VERSION_DURING) — kill fired AFTER binary swap?" >&2
    exit 1
fi
echo "  ✓ ./sb binary still at $SB_VERSION_BEFORE (no swap yet)"
echo "  ✓ RED confirmed: flag PreSwap, working tree advanced, binary unswapped"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — second install for recovery
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery ──"
# The recovery reads the PreSwap flag → recoverFromFlag PreSwap branch
# (service.go:822) → recoveryRollback → rollback() → os.Exit(75), the documented
# "UPGRADE FAILED, ROLLED BACK" handoff. install_statbus_in_vm propagates that
# exit code, so tolerate 75 specifically; any other non-zero is a real recovery
# failure and aborts. (Mirror of 2-preswap-backup-kill:223.)
install_statbus_in_vm "$VM_NAME" || { rc=$?; [ "$rc" -eq 75 ] || exit "$rc"; }

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# C4 recovery is an ABORT (same shape as C3): no commit at the binary-
# swap boundary → terminal state must be 'failed' or 'rolled_back'.
# The load-bearing additional check (vs C3) is that the working tree
# went BACK to the old commit — restoreGitState's job.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

FINAL_STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    failed|rolled_back)
        echo "  ✓ row reached a principled ABORT terminal state ($FINAL_STATE)"
        ;;
    completed)
        echo "✗ row state='completed' is NOT valid for a preswap-checkout kill — the upgrade was never committed at the binary-swap boundary" >&2
        exit 1
        ;;
    *)
        echo "✗ unexpected terminal state: $FINAL_STATE" >&2
        exit 1
        ;;
esac

# The error column must name the PreSwap-guard rollback reason — proves this was
# the recoverFromFlag :822 PreSwap rollback (ErrInstallPreconditionFailed =
# "INSTALL_PRECONDITION_FAILED", service.go:1501), carried in the error prefix on
# both the rolled_back and failed tiers above.
assert_upgrade_row_error_matches "$VM_NAME" "INSTALL_PRECONDITION_FAILED"

# Load-bearing: restoreGitState returned us to OLD_COMMIT.
WT_COMMIT_AFTER=$(VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d '\r' || echo "")
if [ "$WT_COMMIT_AFTER" != "$OLD_COMMIT" ]; then
    echo "✗ working tree not restored to OLD ($WT_COMMIT_AFTER vs $OLD_COMMIT) — restoreGitState path broken" >&2
    exit 1
fi
echo "  ✓ working tree restored to $(echo "$OLD_COMMIT" | cut -c1-8)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"

SB_VERSION_AFTER=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
if [ "$SB_VERSION_AFTER" != "$SB_VERSION_BEFORE" ]; then
    echo "✗ ./sb binary advanced after recovery ($SB_VERSION_BEFORE → $SB_VERSION_AFTER) — abort should not roll forward" >&2
    exit 1
fi
echo "  ✓ ./sb binary still at $SB_VERSION_BEFORE (abort, no roll-forward)"

assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 2-preswap-checkout-kill (C4 abort path; working tree restored, OLD version live, data intact)"
