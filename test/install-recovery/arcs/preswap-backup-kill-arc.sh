#!/bin/bash
# Arc: preswap-backup-kill  (STATBUS-071 §9(5) / doc-016 — 5b, CAT-A)
#
# Reshape of the legacy 2-preswap-backup-kill (C3) onto the kill-arc driver. The
# CRASH is identical (REAL killed-by-system-during-preswap-backup inject, exec.go:618,
# mid-rsync — AFTER rsync-into-syncing, BEFORE rename(syncing→active)); only the
# SCHEDULING swapped (fabricate_scheduled_upgrade_row → real register+schedule, 086)
# and the baseline (v2026.05.2 → base_sha). Crash-shape contract preserved verbatim.
#
# A→B killed mid-backup → RED: flag PreSwap, pre-upgrade-SYNCING on disk + NO
# pre-upgrade-active (caught at the pre-commit moment; a partial syncing is
# restore-invisible), ./sb still A. Recovery (./sb install) → PreSwap-guard abort →
# failed/rolled_back; the partial syncing is NEVER promoted to active; data intact.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-preswap-backup-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-during-preswap-backup"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: preswap-backup-kill  (C3 — kill mid-backup, real inject + real schedule)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
sb_version()    { VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" 2>/dev/null | tr -d '\r' || echo ""; }
dir_present()   { VM_EXEC bash -c "test -d ~/statbus-backups/$1 && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }

# ── A: install + prepare; register B; schedule daemon-down; dispatch with the kill ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
SB_VERSION_BEFORE=$(sb_version)
echo "  pre-trigger ./sb version (A's binary): $SB_VERSION_BEFORE"

arc_schedule_daemon_down "$B_FULL"
arc_install_dispatch_with_inject "$INJECT_CLASS"

# ── RED: flag PreSwap; pre-upgrade-syncing present + NO active; binary unswapped ──
echo ""
echo "── verifying C3 RED state (mid-backup: syncing present, no active) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || { echo "✗ expected flag file present after the kill" >&2; exit 1; }
# (DB stopped for the consistent backup, upstream of the kill → row-state deferred to convergence.)
[ "$(dir_present pre-upgrade-syncing)" = "yes" ] || { echo "✗ no pre-upgrade-syncing dir — kill fired before rsync, or the active→syncing rename-aside didn't happen" >&2; VM_EXEC bash -c "ls -la ~/statbus-backups/ 2>/dev/null" >&2 || true; exit 1; }
[ "$(dir_present pre-upgrade-active)" = "no" ] || { echo "✗ pre-upgrade-active present at the kill point — the syncing→active commit should NOT have run yet" >&2; exit 1; }
echo "  ✓ pre-upgrade-syncing present, no -active (caught pre-commit; partial is restore-invisible)"
SB_DURING=$(sb_version)
[ "$SB_DURING" = "$SB_VERSION_BEFORE" ] || { echo "✗ ./sb binary changed during preswap-backup ($SB_VERSION_BEFORE → $SB_DURING)" >&2; exit 1; }
echo "  ✓ ./sb binary still A — RED confirmed (flag PreSwap, syncing-not-active, unswapped)"

# ── recovery: ./sb install → PreSwap-guard abort ──
echo ""
echo "── recovery: ./sb install (PreSwap-guard abort) ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" || REC_RC=$?
echo "  recovery ./sb install exit: $REC_RC (0 or 75=rolled-back both OK)"

# ── convergence: ABORT (never completed); data intact; partial never promoted ──
echo ""
echo "── convergence checks ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    failed|rolled_back) echo "  ✓ principled ABORT terminal state ($FINAL_STATE)" ;;
    completed) echo "✗ state='completed' invalid for a preswap-backup kill (never committed at binary-swap)" >&2; exit 1 ;;
    *) echo "✗ unexpected terminal state: $FINAL_STATE" >&2; exit 1 ;;
esac
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
SB_AFTER=$(sb_version)
[ "$SB_AFTER" = "$SB_VERSION_BEFORE" ] || { echo "✗ ./sb binary advanced after recovery ($SB_VERSION_BEFORE → $SB_AFTER) — abort should not roll forward" >&2; exit 1; }
echo "  ✓ ./sb binary still A (abort, no roll-forward)"
# Load-bearing: the partial syncing must NEVER have been promoted to a restorable active.
[ "$(dir_present pre-upgrade-active)" = "no" ] || { echo "✗ pre-upgrade-active present after a preswap-backup ABORT — a partial was wrongly promoted to a restorable snapshot" >&2; exit 1; }
echo "  ✓ no pre-upgrade-active after abort (partial never promoted)"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: preswap-backup-kill (kill mid-rsync → syncing-not-active; abort kept A, data intact; partial never promoted)"
