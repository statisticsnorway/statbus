#!/bin/bash
# Scenario 21: preswap-backup-kill  (C3 / Layer 2 kill — preswap backup phase)
#
# Class:                 killed-by-system-during-preswap-backup
# Class kind:            Kill
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   A process killed inside `backupDatabase` AFTER rsync finishes but
#   BEFORE the atomic rename (`pre-upgrade-<stamp>.tmp` → `pre-upgrade-
#   <stamp>`) leaves the system with: flag PreSwap (not PostSwap — the
#   kill fired upstream of `updateFlagPostSwap`), backup .tmp directory
#   on disk with rsync-complete contents but never finalized, OLD
#   binary on disk (binary swap happens later in executeUpgrade), DB
#   volume unmodified (rsync was COPY-only; source was read-only mount).
#
#   Recovery via the next install's recoverFromFlag → PreSwap branch:
#   discard the .tmp directory (pruneStaleTmpBackups handles it OR
#   the PreSwap recovery cleans it explicitly), restart services at
#   the OLD binary + OLD DB volume, clear the flag, mark the upgrade
#   row state='failed'. Convergence: system healthy at OLD version,
#   data intact (DB was never touched — rsync ran source-read-only).
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2 — provides a
#      migration delta so the upgrade actually runs through executeUpgrade).
#   2. Populate via populate_with_demo_data.
#   3. Snapshot data counts (R5 cross-check — the backup path mustn't
#      mutate the source volume).
#   4. Run first install at HEAD with
#      STATBUS_INJECT_AT=killed-by-system-during-preswap-backup.
#      inject.KillHere fires inside backupDatabase after rsync but
#      before the rename; install exits 137 with: flag present, .tmp
#      dir on disk, OLD binary still in place.
#   5. Verify RED state: flag file present; upgrade row='in_progress';
#      backup .tmp dir on disk (not yet renamed to final name); ./sb
#      binary is the OLD version (no swap happened).
#   6. Run a SECOND install (no env vars) for recovery.
#   7. Assert convergence: row state='failed' or 'rolled_back' (the
#      PreSwap branch maps to "abort" rather than "complete" — the
#      upgrade was never committed at the binary-swap boundary, so
#      'completed' is NOT a valid terminal state for this RED). Data
#      intact. Flag absent. .tmp dir cleaned up. ./sb binary still OLD
#      (the recovery aborted, did not roll forward to HEAD).
#
# Hetzner-runnability:
#   READY. Injection site lands with this commit. PreSwap branch of
#   recoverFromFlag already exists on master + this branch — has
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

# Baseline ./sb version on disk BEFORE the trigger. The C3 wedge leaves
# the binary UNCHANGED (binary swap happens later in executeUpgrade),
# so this version must match post-recovery too.
SB_VERSION_BEFORE=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
echo "  pre-trigger ./sb version: $SB_VERSION_BEFORE"

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
cp /tmp/sb ./sb
chmod +x ./sb
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=killed-by-system-during-preswap-backup \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
scp "${SSH_OPTS[@]}" -q "$INSTALL_SCRIPT" root@"$ip":/tmp/install-c3.sh
rm -f "$INSTALL_SCRIPT"
upload_sb_to_vm "$VM_NAME"

set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" root@"$ip" "sudo -u statbus bash /tmp/install-c3.sh"
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
assert_upgrade_row_state "$VM_NAME" "in_progress"

# C3-specific: a `pre-upgrade-*.tmp` directory MUST exist under the
# backup root. Filtering on the .tmp suffix to ensure we caught the
# kill at the pre-rename moment (not post-rename, which would suggest
# the kill site fired in the wrong place).
TMP_BACKUP_COUNT=$(VM_EXEC bash -c "ls -d ~/statbus-backups/pre-upgrade-*.tmp 2>/dev/null | wc -l | tr -d ' '" || echo "0")
if [ "$TMP_BACKUP_COUNT" = "0" ]; then
    echo "✗ no pre-upgrade-*.tmp directory on disk — kill fired before rsync started?" >&2
    VM_EXEC bash -c "ls -la ~/statbus-backups/ 2>/dev/null" >&2 || true
    exit 1
fi
echo "  ✓ pre-upgrade-*.tmp directory(ies) present ($TMP_BACKUP_COUNT)"

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
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@test.service" 2

echo ""
echo "PASS: preswap-backup-kill (preswap kill aborted cleanly; OLD version live, data intact, partial backup cleaned up)"
