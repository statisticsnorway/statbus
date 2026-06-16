#!/bin/bash
# Scenario: 2-preswap-checkout-kill  (C4 / Layer 2 kill — preswap git checkout)
#
# Class:                 killed-by-system-during-preswap-checkout
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed in executeUpgrade AFTER the target's objects are
#   fetched but BEFORE the binary swap leaves the system with: working
#   tree STILL at the SOURCE commit (STATBUS-060: the pre-swap
#   `git checkout` was removed — checkout is deferred to the recovery
#   boot so the OLD binary never materializes target-compose), backup
#   .tmp dir already finalized, OLD binary on disk, flag PreSwap.
#   Recovery via the next install's recoverFromFlag → PreSwap branch:
#   the recovery boot does the deferred `git checkout flag.CommitSHA`,
#   then restoreGitState reverts the working tree back to source via
#   the `pre-upgrade` branch pinned at the start of executeUpgrade,
#   discards the backup, clears the flag, marks the upgrade row
#   'failed' or 'rolled_back'. Convergence: working tree at SOURCE
#   commit, OLD binary live, data intact.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2).
#   2. Populate via populate_with_demo_data.
#   3. Snapshot data counts.
#   4. Snapshot HEAD commit on the VM (post-bootstrap; this is the
#      OLD commit that restoreGitState must return us to).
#   5. Run first install at HEAD-local with
#      STATBUS_INJECT_AT=killed-by-system-during-preswap-checkout.
#      inject.KillHere fires in executeUpgrade AFTER git fetch
#      completes but NO checkout happens (STATBUS-060: deferred to
#      recovery boot). Install exits 137 with: flag present (PreSwap),
#      backup dir finalized, working tree STILL at OLD_COMMIT (source),
#      ./sb binary still OLD (no swap yet).
#   6. Verify RED: flag file present; working tree STILL at OLD_COMMIT
#      (source — no executeUpgrade checkout happened); ./sb binary
#      still the OLD version. (DB is down; row state verified in
#      Phase 6 after recovery brings the DB back up.)
#   7. Run a SECOND install (no env vars) for recovery.
#   8. Assert convergence: row state='failed' or 'rolled_back';
#      working tree BACK at the OLD commit (the pre-upgrade branch
#      target); data intact; flag absent; backup dir cleaned up;
#      ./sb still OLD.
#
# Hetzner-runnability:
#   READY. Injection site lands with this commit. PreSwap branch's
#   restoreGitState is the canonical recovery path; the working tree
#   stays at source (no pre-swap checkout — STATBUS-060).
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
echo "  Scenario: 2-preswap-checkout-kill  (C4 / Layer 2 kill — preswap fetch, deferred checkout)"
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
# STATBUS-060: do NOT checkout here. executeUpgrade also defers the
# working-tree checkout to the recovery boot — the OLD binary must never
# see target-compose. Pre-fetching objects is still needed so that
# executeUpgrade's `git fetch origin commitSHA` is a fast no-op.
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

# STATBUS-060 NOTE: the setup script above pre-fetches HEAD's objects
# (git cat-file + git fetch if needed) but does NOT do a working-tree
# checkout. executeUpgrade also does NOT checkout the working tree before
# the binary swap (deferred to the recovery boot). So when the C4 kill
# fires, the working tree is STILL at OLD_COMMIT — accurately modelling
# the production state where the OLD binary never sees target-compose.

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

# Working tree STILL at OLD_COMMIT (STATBUS-060: executeUpgrade no longer
# does a pre-swap checkout; checkout is deferred to the recovery boot).
# This is the load-bearing property of the defer-checkout fix: the OLD
# binary never materializes target-compose on disk.
WT_COMMIT_DURING=$(VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d '\r' || echo "")
if [ "$WT_COMMIT_DURING" != "$OLD_COMMIT" ]; then
    echo "✗ working tree advanced during preswap-checkout kill ($WT_COMMIT_DURING vs expected OLD_COMMIT=$OLD_COMMIT)" >&2
    echo "  executeUpgrade must NOT checkout the working tree before binary swap (STATBUS-060)." >&2
    exit 1
fi
echo "  ✓ working tree still at OLD_COMMIT ($(echo "$OLD_COMMIT" | cut -c1-8)) — no pre-swap checkout"

# ./sb binary still OLD (binary swap is downstream of C4).
SB_VERSION_DURING=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
if [ "$SB_VERSION_DURING" != "$SB_VERSION_BEFORE" ]; then
    echo "✗ ./sb binary changed during preswap-checkout phase ($SB_VERSION_BEFORE → $SB_VERSION_DURING) — kill fired AFTER binary swap?" >&2
    exit 1
fi
echo "  ✓ ./sb binary still at $SB_VERSION_BEFORE (no swap yet)"
echo "  ✓ RED confirmed: flag PreSwap, working tree at source (not target), binary unswapped"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — second install for recovery
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery ──"
# The recovery reads the PreSwap flag → recoverFromFlag PreSwap branch →
# recoveryRollback reads from_commit_sha (set at claim while HEAD was still at
# source CommitSHA — STATBUS-060 deferred checkout; architect's STATBUS-062) →
# restoreGitState(source CommitSHA) → rollback() → os.Exit(75). Tolerate 75;
# any other non-zero is a real recovery failure. (Mirror of 2-preswap-backup-kill.)
install_statbus_in_vm "$VM_NAME" || { rc=$?; [ "$rc" -eq 75 ] || exit "$rc"; }

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# C4 recovery is an ABORT: no commit at binary-swap boundary → terminal state
# 'failed' or 'rolled_back'. Load-bearing: working tree must return to the source
# CommitSHA — recoveryRollback uses from_commit_sha (= source CommitSHA, captured
# at claim while HEAD was still at source; STATBUS-060 + STATBUS-062).
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

# Load-bearing: working tree returned to source CommitSHA via from_commit_sha → restoreGitState.
WT_COMMIT_AFTER=$(VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d '\r' || echo "")
if [ "$WT_COMMIT_AFTER" != "$OLD_COMMIT" ]; then
    echo "✗ working tree not restored to source CommitSHA $OLD_COMMIT (got $WT_COMMIT_AFTER) — from_commit_sha/restoreGitState path broken" >&2
    exit 1
fi
echo "  ✓ working tree at source CommitSHA $(echo "$OLD_COMMIT" | cut -c1-8)"

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
echo "PASS: 2-preswap-checkout-kill (C4 abort path; working tree at source CommitSHA, release unchanged, data intact)"
