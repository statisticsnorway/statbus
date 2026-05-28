#!/bin/bash
# Scenario 21: preswap-backup-kill  (C3 / Layer 2 kill — preswap backup phase)
#
# Class:                 killed-by-system-during-preswap-backup
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior (CHANGE 2 / task #12 — also the
# "kill-mid-rsync-resumable" coverage):
#   A process killed inside `backupDatabase` AFTER rsync finishes but BEFORE the
#   atomic commit rename (`pre-upgrade-syncing` → `pre-upgrade-active`) leaves:
#   flag PreSwap (kill fired upstream of `updateFlagPostSwap`), a
#   pre-upgrade-SYNCING directory with rsync-complete contents but NOT committed
#   (no pre-upgrade-active), OLD binary on disk (binary swap is downstream), DB
#   volume unmodified (rsync was COPY-only, source read-only mount).
#
#   The partial syncing is structurally invisible to pickLatestBackup (which
#   reads ONLY pre-upgrade-active), so it can never be restored as if complete —
#   and it is NEVER deleted: a future upgrade's backupDatabase RESUMES into it
#   (the incremental base). Recovery via the next install's recoverFromFlag →
#   PreSwap branch: abort (restart services at OLD binary + OLD DB volume, clear
#   the flag, mark the row state='failed'). Convergence: healthy at OLD version,
#   data intact, and the partial NEVER promoted to a restorable snapshot
#   (pre-upgrade-active absent post-abort).
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2 — provides a
#      migration delta so the upgrade actually runs through executeUpgrade).
#   2. Populate via populate_with_demo_data.
#   3. Snapshot data counts (R5 cross-check — the backup path mustn't
#      mutate the source volume).
#   4. Run first install at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-during-preswap-backup.
#      inject.KillHere fires inside backupDatabase after rsync-into-syncing
#      but before rename(syncing→active); install exits 137 with: flag
#      present, pre-upgrade-syncing dir on disk (no active), OLD binary
#      still in place.
#   5. Verify RED state: flag file present; upgrade row='in_progress';
#      pre-upgrade-syncing present + no pre-upgrade-active (caught
#      pre-commit); ./sb binary is the OLD version (no swap happened).
#   6. Run a SECOND install (no env vars) for recovery.
#   7. Assert convergence: row state='failed' or 'rolled_back' (the
#      PreSwap branch maps to "abort" rather than "complete" — the
#      upgrade was never committed at the binary-swap boundary, so
#      'completed' is NOT a valid terminal state for this RED). Data
#      intact. Flag absent. NO pre-upgrade-active (the partial was never
#      promoted to a restorable snapshot). ./sb binary still OLD (the
#      recovery aborted, did not roll forward to HEAD).
#
# Hetzner-runnability:
#   READY. The injection site + the active/syncing scheme are on master
#   (merge 86fb9a454). PreSwap branch of recoverFromFlag has
#   handled the "clean abort, no commit" terminal state since the
#   Fix 5b forward-then-restore design.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/21-preswap-backup-kill.sh \
#     statbus-recovery-21

set -euo pipefail

VM_NAME="${1:-statbus-recovery-21}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 21: preswap-backup-kill  (C3 / Layer 2 kill — backup phase)"
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
# Phase 3 — first install at HEAD with C3 kill injection
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── first install at HEAD with C3 kill injection ──"
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
STATBUS_INJECT_AT=killed-by-system-during-preswap-backup \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-c3.sh
upload_sb_to_vm "$VM_NAME"

# Baseline ./sb version AFTER upload_sb_to_vm (which is itself a binary swap —
# the harness replaces the v2026.05.2 binary with HEAD's so the test exercises
# HEAD's code). The "binary unchanged" assertions below verify that the UPGRADE's
# OWN executeUpgrade-internal binary-swap step (replaceBinaryOnDisk) has NOT yet
# run at the C3 kill point — which fires inside backupDatabase, UPSTREAM of the
# upgrade's binary swap. So the right baseline is the HEAD binary the harness
# just installed; the assertion catches a regression where the upgrade's
# internal swap accidentally runs pre-backup. (Pre-fix this snapshot was taken
# BEFORE upload_sb_to_vm and false-failed: SB_VERSION_BEFORE=v2026.05.2 vs
# SB_VERSION_DURING=HEAD — comparing the harness's setup swap, not the upgrade's
# internal swap. Verification run 26581049544 surfaced it; fix re-baselines.)
SB_VERSION_BEFORE=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
echo "  pre-trigger ./sb version (post-upload baseline): $SB_VERSION_BEFORE"

# Seed a scheduled public.upgrade row at HEAD so the install state detector
# classifies as StateScheduledUpgrade (and dispatches executeUpgrade → backupDatabase
# → the C3 kill site). Without this, RUN 1 sees nothing-scheduled (current==target:
# both derive from the running binary's ldflags version, which is HEAD after
# upload_sb_to_vm overwrote the v2026.05.2 binary) → idempotent step-table refresh
# → exits 0 → KillHere never fires. Pattern-A fix (harness regression run 26539222000).
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-c3.sh"
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
echo "── verifying canonical C3 RED state ──"

VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after kill" >&2
    exit 1
}
# NOTE: do NOT assert public.upgrade.state='in_progress' here — at this point
# the DB container has been stopped (executeUpgrade stops it before
# backupDatabase, log line "Stopping database..." just upstream of the kill),
# so `./sb psql` would fail with "connection refused" and assert_upgrade_row_state
# would `return 1` under `set -e` → silent script exit before any post-kill
# assertion. The flag-file `ls` above already proves "upgrade was in-flight when
# killed" (and the flag carries Phase=PreSwap, holder, PID etc. as the canonical
# crash-survivable state per CLAUDE.md's flag-file-ownership-contract). The
# row-state convergence check belongs in Phase 6 below, where the recovery
# install has restarted the DB. (Pre-CHANGE-2 this assertion happened to
# coincide with a still-running DB; under the post-#12 + STATBUS_*_INJECT_AT=...
# kill flow the DB is stopped before backupDatabase, so the assertion now
# false-fails silently. Fix: drop the redundant RED-phase row-state check; the
# flag file IS the correct source of truth at the kill point.)

# C3-specific (CHANGE 2 / #12): the kill fires inside backupDatabase AFTER
# rsync-into-syncing but BEFORE rename(syncing→active) (exec.go
# killed-by-system-during-preswap-backup). So the RED state is a
# pre-upgrade-SYNCING dir present and NO pre-upgrade-active — proving we caught
# the kill at the pre-commit moment. (Pre-#12 this was a pre-upgrade-<stamp>.tmp
# dir; the persistent active/syncing scheme replaced it.) A partial syncing is
# structurally invisible to pickLatestBackup, so it can never be restored as if
# complete; the next run RESUMES into it (never deletes it).
SYNCING_PRESENT=$(VM_EXEC bash -c "test -d ~/statbus-backups/pre-upgrade-syncing && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no")
ACTIVE_PRESENT=$(VM_EXEC bash -c "test -d ~/statbus-backups/pre-upgrade-active && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no")
if [ "$SYNCING_PRESENT" != "yes" ]; then
    echo "✗ no pre-upgrade-syncing directory on disk — kill fired before rsync started, or the active→syncing rename-aside did not happen?" >&2
    VM_EXEC bash -c "ls -la ~/statbus-backups/ 2>/dev/null" >&2 || true
    exit 1
fi
if [ "$ACTIVE_PRESENT" = "yes" ]; then
    echo "✗ pre-upgrade-active present at the kill point — the syncing→active commit rename should NOT have run yet (kill fired in the wrong place?)" >&2
    exit 1
fi
echo "  ✓ pre-upgrade-syncing present, no pre-upgrade-active (caught at the pre-commit moment; partial is restore-invisible)"

# Sanity: ./sb binary still the OLD version (binary swap is downstream).
SB_VERSION_DURING=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
if [ "$SB_VERSION_DURING" != "$SB_VERSION_BEFORE" ]; then
    echo "✗ ./sb binary changed during preswap-backup phase ($SB_VERSION_BEFORE → $SB_VERSION_DURING) — kill fired AFTER binary swap?" >&2
    exit 1
fi
echo "  ✓ ./sb binary still at $SB_VERSION_BEFORE (no swap yet)"
echo "  ✓ RED confirmed: flag PreSwap, .tmp backup on disk, binary unswapped"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — second install for recovery
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery ──"
install_statbus_in_vm "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# C3 recovery is an ABORT, not a complete. The upgrade was never
# committed at the binary-swap boundary, so the principled terminal
# state is 'failed' or 'rolled_back'. The OLD version is the live
# version after recovery; data intact (rsync was source-read-only).
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
        echo "✗ row state='completed' is NOT valid for a preswap-backup kill — the upgrade was never committed at the binary-swap boundary" >&2
        echo "  Either the recovery rolled forward incorrectly, or the kill site did not fire pre-binary-swap." >&2
        exit 1
        ;;
    *)
        echo "✗ unexpected terminal state: $FINAL_STATE" >&2
        exit 1
        ;;
esac

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
# After abort, ./sb should still be the OLD version.
SB_VERSION_AFTER=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
if [ "$SB_VERSION_AFTER" != "$SB_VERSION_BEFORE" ]; then
    echo "✗ ./sb binary advanced after recovery ($SB_VERSION_BEFORE → $SB_VERSION_AFTER) — abort should not roll forward" >&2
    exit 1
fi
echo "  ✓ ./sb binary still at $SB_VERSION_BEFORE post-recovery (abort, no roll-forward)"

# CHANGE-2 (#12) backup-state coherence after the preswap-kill abort. The
# killed run left pre-upgrade-syncing (no active). The PreSwap recovery aborts
# (no new backup), so syncing legitimately persists as the resumable
# incremental base (NEVER deleted — a future upgrade resumes into it). The
# load-bearing invariant: a partial syncing must NEVER masquerade as a
# restorable snapshot — i.e. it must NOT have been renamed to active by the
# abort path (only a successful rsync→fsync→rename does that). So: active
# absent is the correct post-abort state (no completed backup was produced);
# syncing present-or-consumed are both fine. assert_no_orphan_backup (managed-
# dir-aware) already confirms no LEGACY orphan accumulated.
POST_ACTIVE=$(VM_EXEC bash -c "test -d ~/statbus-backups/pre-upgrade-active && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no")
if [ "$POST_ACTIVE" = "yes" ]; then
    echo "✗ pre-upgrade-active present after a preswap-kill ABORT — a partial backup was wrongly promoted to a restorable snapshot (syncing→active must only happen on a COMPLETE rsync, never on the abort path)" >&2
    exit 1
fi
echo "  ✓ no pre-upgrade-active after abort (the partial was never promoted to a restorable snapshot)"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: preswap-backup-kill (CHANGE-2: kill mid-rsync left pre-upgrade-syncing not active; abort kept OLD version, data intact; the partial was never promoted to a restorable snapshot)"
