#!/bin/bash
# Arc: preswap-binary-swap-kill  (STATBUS-071 §9(5) / doc-016 — 5b, CAT-A)
#
# Reshape of the legacy 2-preswap-binary-swap-kill (C5) onto the kill-arc driver.
# CRASH identical (REAL killed-by-system-during-binary-swap inject, service.go:4326,
# at the binary-swap boundary — still PreSwap: the post-swap stamp hasn't been
# written); only the SCHEDULING swapped (fabricate → real register+schedule, 086)
# and the baseline (v2026.05.2 → base_sha). Crash-shape contract preserved.
#
# A→B killed at the binary-swap boundary → RED: flag PreSwap (DB stopped for the
# consistent backup → row/migration checks deferred). Recovery (./sb install) →
# recoverFromFlag :822 PreSwap branch → recoveryRollback → rollback (UNCONDITIONAL,
# before the :846 forward-recovery) → NEVER 'completed'; row rolled_back/failed
# with INSTALL_PRECONDITION_FAILED; db.migration unchanged (migrate is post-swap,
# never reached); data intact.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-preswap-binary-swap-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-during-binary-swap"

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

# _dump_preswap_binary_swap_kill_failure_diagnostics — STATBUS-155 rider
# (mirrors postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics):
# on ANY non-zero exit, pull B's own upgrade progress log + the daemon journal
# + its row state to STDERR before cleanup_vm reaps the VM, so a red run is
# self-sufficient without needing a kept VM. Best-effort throughout (|| true)
# — a diagnostics failure must never mask the real assertion error that
# triggered this trap.
_dump_preswap_binary_swap_kill_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (B's progress log + daemon journal + row state) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── B's upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    else
        echo "  (no log_relative_file_path found for B's row — row absent or DB unreachable)" >&2
    fi
    echo "── daemon journal (statbus-upgrade@statbus.service, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit (B's row, commit_sha = ${B_FULL:-?}) ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(recovery_parked_reason,''), error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_preswap_binary_swap_kill_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: preswap-binary-swap-kill  (C5 — kill at binary-swap boundary, real inject + real schedule)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare; capture baseline migration max; register; schedule; dispatch+kill ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
BASELINE_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline db.migration max_version: $BASELINE_MAX_VERSION"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"
arc_install_dispatch_with_inject "$INJECT_CLASS"

# ── RED: flag PreSwap (DB down for the backup → row/migration checks deferred) ──
echo ""
echo "── verifying C5 RED state (flag PreSwap; DB down) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || { echo "✗ expected flag file present after the kill" >&2; exit 1; }
echo "  ✓ flag present (Phase=PreSwap); row/migration checks deferred to convergence (DB down for the backup)"

# ── recovery: ./sb install → :822 PreSwap-guard rollback (NEVER forward-recover) ──
echo ""
echo "── recovery: ./sb install (PreSwap-guard rollback) ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" || REC_RC=$?
echo "  recovery ./sb install exit: $REC_RC (0 or 75=rolled-back both OK)"

# ── convergence: NEVER completed (the :822 guard rolls back before forward-recovery) ──
echo ""
echo "── convergence checks ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
if [ "$FINAL_STATE" = "completed" ]; then
    echo "✗ state='completed' — a PreSwap kill must NOT forward-recover; the :822 guard rolls back before the :846 forward-recovery branch (guard regressed?)" >&2
    exit 1
fi
case "$FINAL_STATE" in
    rolled_back) echo "  ✓ rolled back to A (clean PreSwap-guard rollback)" ;;
    failed)      echo "  ⚠ terminal 'failed' (degraded — :822 guard fired but the rollback's own restore tripped); a valid PreSwap-abort terminal" ;;
    *)           echo "✗ unexpected terminal state: $FINAL_STATE (expected rolled_back or failed)" >&2; exit 1 ;;
esac
# The error column names the PreSwap-guard rollback reason (recoverFromFlag :822).
assert_upgrade_row_error_matches "$VM_NAME" "INSTALL_PRECONDITION_FAILED"
# Migrations never applied (migrate is post-swap, never reached) + rollback restored the snapshot.
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: preswap-binary-swap-kill (PreSwap kill → :822 guard rollback; row $FINAL_STATE with INSTALL_PRECONDITION_FAILED, migrations unchanged, data intact)"
