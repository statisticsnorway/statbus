#!/bin/bash
# Arc: postswap-container-restart-kill  (STATBUS-071 §9(5) / doc-016 — 5b, CAT-A)
#
# Reshape of the legacy 3-postswap-container-restart-kill (C8) onto the kill-arc
# driver. CRASH identical (REAL killed-by-system-during-container-restart inject,
# service.go:4779 — POSTSWAP: binary swapped, migrations applied, flag pinned
# Phase=Resuming, DB UP); only the SCHEDULING swapped (fabricate → real
# register+schedule, 086) + the baseline (v2026.05.2 → base_sha). Contract preserved.
#
# A→B killed during the post-swap container restart → RED: flag (Phase=NewSbUpgrading) +
# row in_progress (DB up; migrations applied; containers indeterminate). Recovery
# (./sb install) → recoverFromFlag reads observed-state already-at-new (binary + migrations
# at B, containers healthy) → resumeNewSb SELF-HEALS the row to 'completed' without re-running
# the pipeline — the serve-proven convergence contract (STATBUS-039/160/192/193). Terminal
# 'completed' via [completed-self-heal]; the forward-converged box keeps B's data (no rollback).
# STATBUS-201: this replaced the RETIRED pre-039 "Resuming one-shot latch → rollback" assert,
# which cited the long-gone service.go:755 and demanded a rollback the product no longer does.
# The adjacent postswap-converged-selfheal arc deliberately proves the same class in the
# ~ms-later converged-but-unlanded window.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-container-restart-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-during-container-restart"

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

# _dump_container_restart_kill_failure_diagnostics — STATBUS-155 rider (mirrors
# postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics): on ANY
# non-zero exit, pull B's own upgrade progress log + the daemon journal + its
# row state to STDERR before cleanup_vm reaps the VM, so a red run is
# self-sufficient without needing a kept VM. Best-effort throughout (|| true)
# — a diagnostics failure must never mask the real assertion error that
# triggered this trap.
_dump_container_restart_kill_failure_diagnostics() {
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

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_container_restart_kill_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-container-restart-kill  (C8 — kill during post-swap restart, real inject + real schedule)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

# STATBUS-293: filtered to B. An UNFILTERED probe reads whatever row has
# the highest id, and upgrade discovery registers candidate rows at any
# moment — so the assert silently starts reporting on a row the scenario
# never touched. Mirrors this arc's own diagnostic query.
upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare; register; schedule daemon-down; dispatch with the kill ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"
arc_install_dispatch_with_inject "$INJECT_CLASS"

# ── RED: flag present + row in_progress (POSTSWAP — DB is UP) ──
echo ""
echo "── verifying C8 RED state (flag present; row in_progress; DB up) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || { echo "✗ expected flag file present after the kill" >&2; exit 1; }
assert_upgrade_row_state "$VM_NAME" "in_progress" "$B_FULL"
echo "  ✓ RED confirmed: flag present + row in_progress (migrations applied; containers indeterminate)"

# ── recovery: ./sb install → recoverFromFlag → resumeNewSb serve-proven self-heal → completed ──
echo ""
echo "── recovery: ./sb install (recoverFromFlag observed already-at-new → resumeNewSb self-heal → completed) ──"
REC_RC=0
REC_OUT=$(VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf 2>&1") || REC_RC=$?
echo "$REC_OUT" | tail -40
echo "  recovery ./sb install exit: $REC_RC (0 or 75 both admissible)"

# ── convergence: serve-proven SELF-HEAL to completed (never the retired rollback) ──
echo ""
echo "── serve-proven convergence checks (self-heal to completed, not the retired rollback) ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
[ "$FINAL_STATE" = "completed" ] || { echo "✗ state='$FINAL_STATE' — the container-restart kill must converge FORWARD via resumeNewSb's containers-at-target self-heal to 'completed' (STATBUS-039/192/193); a non-completed terminal means the serve-proven self-heal regressed" >&2; exit 1; }
# The PRODUCT's own self-heal label in the recovery output — proves resumeNewSb's containers-at-target
# branch (not applyNewSbUpgrading re-run, not the flagless belt) converged THIS row.
echo "$REC_OUT" | grep -qF "upgrade row [completed-self-heal]" || { echo "✗ recovery output lacks resumeNewSb's [completed-self-heal] label — the row did not converge via the containers-at-target self-heal" >&2; exit 1; }
# The RETIRED Resuming one-shot latch must NOT have fired — a death BEFORE resume (this arc's kill)
# converges forward; UPGRADE_DIED_DURING_RESUME is the latch's marker and must be ABSENT.
if echo "$REC_OUT" | grep -qF "UPGRADE_DIED_DURING_RESUME"; then
    echo "✗ UPGRADE_DIED_DURING_RESUME in the recovery output — the RETIRED Resuming one-shot latch fired instead of the serve-proven self-heal (STATBUS-201 regression)" >&2
    exit 1
fi
assert_upgrade_row_state "$VM_NAME" "completed" "$B_FULL"
# Data intact at B — no rollback; the self-heal keeps the forward-converged box (V is schema-only,
# counts match the pre-trigger snapshot, mirroring the converged-selfheal arc).
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: postswap-container-restart-kill (death during post-swap container restart → recoverFromFlag observed already-at-new → resumeNewSb serve-proven self-heal to 'completed' [completed-self-heal]; the retired Resuming-latch rollback is gone; flag absent, data intact, NRestarts bounded)"
