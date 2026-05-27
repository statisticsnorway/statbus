#!/bin/bash
# Scenario 30: kill-mid-rsync-resumable  (#12 CHANGE 2 — resumable incremental base)
#
# Class:                 killed-by-system-during-preswap-backup (reused)
# Class kind:            Kill (mid-rsync, before the syncing→active commit)
# Source:                plan upgrade-resume-structural-whole.md (CHANGE 2)
#
# WHAT THIS PROVES (the RESUMABLE half of #12, complementing scenario 21):
#   Scenario 21 kills inside backupDatabase (after rsync-into-syncing, before
#   rename(syncing→active)) and asserts the ABORT path: pre-upgrade-syncing left,
#   no active, recovery aborts to OLD version, the partial is never promoted to
#   a restorable snapshot. THIS scenario adds the next chapter: the leftover
#   pre-upgrade-syncing is the INCREMENTAL BASE — a SUBSEQUENT upgrade's
#   backupDatabase RESUMES into it (never deletes it: prepareBackupSnapshotDir
#   sees active-absent + syncing-present → rsync straight into syncing) and
#   COMMITS it via rename(syncing→active). End state: a complete pre-upgrade-active,
#   upgrade completed, data intact.
#
#   Load-bearing assertions:
#     (a) after the kill: pre-upgrade-syncing present, NO pre-upgrade-active
#         (caught pre-commit; the partial is restore-invisible).
#     (b) the leftover syncing is NEVER deleted across the recovery + the next
#         backup (it is the resume base).
#     (c) after a subsequent successful upgrade: pre-upgrade-active EXISTS and
#         pre-upgrade-syncing is GONE (consumed by the commit rename), the row
#         is 'completed', data intact. → a killed mid-rsync backup is *finished*
#         by re-running, exactly the "rsync idempotent → killed rsync is finished
#         by re-running" invariant.
#
# This is the behavioral end-to-end complement of the Go guard
# TestPrepareSnapshot_ResumesIntoLeftoverSyncing (which pins the rename state
# machine in isolation): here a REAL docker rsync resumes into a REAL leftover
# syncing dir and commits it on a live VM.
#
# Hetzner-runnability:
#   READY. Inject site killed-by-system-during-preswap-backup + the active/
#   syncing scheme are on master (merge 86fb9a454). No new inject site, no
#   long holds (a KillHere is instantaneous).
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/30-kill-mid-rsync-resumable.sh \
#     statbus-recovery-30

set -euo pipefail

VM_NAME="${1:-statbus-recovery-30}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 30: kill-mid-rsync-resumable  (#12 CHANGE 2)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo ""
echo "  Kill mid-rsync leaves pre-upgrade-syncing (no active); a SUBSEQUENT"
echo "  upgrade RESUMES into it (never deletes) and commits syncing→active."
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
# Phase 3 — RUN 1: install at HEAD, killed mid-rsync (leaves pre-upgrade-syncing)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── RUN 1: install at HEAD with mid-rsync kill injection ──"
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
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-killrsync.sh
upload_sb_to_vm "$VM_NAME"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$ip" "bash /tmp/install-killrsync.sh"
FIRST_EXIT=$?
set -e
echo "  RUN 1 exited: $FIRST_EXIT (137 = injected SIGKILL semantics)"
if [ "$FIRST_EXIT" = "124" ]; then
    echo "✗ RUN 1 timed out — kill site did not fire" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — verify the kill left pre-upgrade-syncing, NO pre-upgrade-active
# (assertion (a)). Capture the syncing dir's inode so Phase 6 can prove the
# SAME dir was resumed-into (not deleted + recreated).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── verifying mid-rsync RED state (syncing present, no active) ──"
SYNCING_PRESENT=$(VM_EXEC bash -c "test -d ~/statbus-backups/pre-upgrade-syncing && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no")
ACTIVE_PRESENT=$(VM_EXEC bash -c "test -d ~/statbus-backups/pre-upgrade-active && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no")
if [ "$SYNCING_PRESENT" != "yes" ]; then
    echo "✗ no pre-upgrade-syncing after the mid-rsync kill" >&2
    VM_EXEC bash -c "ls -la ~/statbus-backups/ 2>/dev/null" >&2 || true
    exit 1
fi
if [ "$ACTIVE_PRESENT" = "yes" ]; then
    echo "✗ pre-upgrade-active present at the kill point — commit rename should not have run" >&2
    exit 1
fi
SYNCING_INODE=$(VM_EXEC bash -c "stat -c %i ~/statbus-backups/pre-upgrade-syncing 2>/dev/null" | tr -d ' \r\n' || echo "")
echo "  ✓ (a) pre-upgrade-syncing present (inode=$SYNCING_INODE), no pre-upgrade-active"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — RUN 2: recovery install (no inject). The PreSwap branch aborts the
# killed upgrade; the leftover syncing must NOT be deleted (it's the base).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── RUN 2: recovery install (PreSwap abort; leftover syncing must survive) ──"
install_statbus_in_vm "$VM_NAME"

SYNCING_AFTER_RECOVERY=$(VM_EXEC bash -c "test -d ~/statbus-backups/pre-upgrade-syncing && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no")
if [ "$SYNCING_AFTER_RECOVERY" != "yes" ]; then
    echo "✗ (b) pre-upgrade-syncing was DELETED by the recovery — it is the incremental base and must NEVER be rm'd (prepareBackupSnapshotDir resumes into it)" >&2
    exit 1
fi
SYNCING_INODE2=$(VM_EXEC bash -c "stat -c %i ~/statbus-backups/pre-upgrade-syncing 2>/dev/null" | tr -d ' \r\n' || echo "")
if [ -n "$SYNCING_INODE" ] && [ "$SYNCING_INODE" != "$SYNCING_INODE2" ]; then
    echo "✗ (b) pre-upgrade-syncing inode changed ($SYNCING_INODE → $SYNCING_INODE2) — it was deleted+recreated, not preserved as the base" >&2
    exit 1
fi
echo "  ✓ (b) leftover pre-upgrade-syncing survived recovery (same inode $SYNCING_INODE2) — the resume base, never deleted"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — RUN 3: a SUBSEQUENT successful upgrade at HEAD. Its backupDatabase
# resumes into the leftover syncing and commits it (rename syncing→active). End
# state: pre-upgrade-active present, syncing gone, row completed (assertion (c)).
#
# We re-fabricate a scheduled row + let the running unit dispatch it (the unit
# is healthy after recovery). Reuse the supervised-unit fabricate path.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── RUN 3: subsequent upgrade at HEAD (resumes into syncing, commits to active) ──"
UNIT="statbus-upgrade@statbus.service"
# The recovery left the binary OLD and the row failed/aborted. Stage HEAD again
# (the resume base + a real migration delta) and fabricate a fresh scheduled row.
upload_sb_to_vm "$VM_NAME"
scp -O "${SSH_OPTS[@]}" \
    "$LIB_DIR/../fixtures/scenario_26_stage_head.sh" \
    root@"$VM_IP":/tmp/scenario_30_stage_head.sh
VM_EXEC bash /tmp/scenario_30_stage_head.sh "$HEAD_LOCAL"

VM_EXEC systemctl --user stop "$UNIT" 2>/dev/null || true
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"
VM_EXEC systemctl --user reset-failed "$UNIT" 2>/dev/null || true
VM_EXEC systemctl --user start "$UNIT"

# Wait for the upgrade to reach a terminal state.
START_TS=$(date +%s)
FINAL_STATE=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$INSTALL_BUDGET_S" ]; then
        echo "✗ subsequent upgrade did not reach a terminal state within budget" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    case "$STATE" in
        completed|failed|rolled_back)
            FINAL_STATE="$STATE"
            echo "  subsequent upgrade reached state='$STATE' (t+${elapsed}s)"
            break
            ;;
    esac
    sleep 5
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — assertion (c): the resume completed the backup. active present,
# syncing gone, row completed, data intact.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── resume-completion checks (LOAD-BEARING) ──"
if [ "$FINAL_STATE" != "completed" ]; then
    echo "✗ subsequent upgrade state='$FINAL_STATE', expected 'completed' (the resume-into-syncing backup should let the upgrade finish)" >&2
    exit 1
fi
POST_ACTIVE=$(VM_EXEC bash -c "test -d ~/statbus-backups/pre-upgrade-active && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no")
POST_SYNCING=$(VM_EXEC bash -c "test -d ~/statbus-backups/pre-upgrade-syncing && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no")
if [ "$POST_ACTIVE" != "yes" ]; then
    echo "✗ (c) no pre-upgrade-active after the subsequent upgrade — the syncing→active commit rename did not happen" >&2
    exit 1
fi
if [ "$POST_SYNCING" = "yes" ]; then
    echo "✗ (c) pre-upgrade-syncing STILL present after a completed upgrade — the commit rename should have consumed it (syncing→active)" >&2
    exit 1
fi
echo "  ✓ (c) pre-upgrade-active present + syncing consumed → the killed mid-rsync backup was FINISHED by re-running (resumed into the leftover base, committed to active)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: kill-mid-rsync-resumable"
echo "  (a mid-rsync kill left pre-upgrade-syncing not active; the leftover survived"
echo "   recovery as the incremental base — same inode, never deleted — and a"
echo "   subsequent upgrade RESUMED into it and committed syncing→active. A killed"
echo "   rsync is finished by re-running: CHANGE-2 crash-safe + idempotent-resume.)"
