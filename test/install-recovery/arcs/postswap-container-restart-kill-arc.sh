#!/bin/bash
# Arc: postswap-container-restart-kill  (STATBUS-071 §9(5) / doc-016 — 5b, CAT-A)
#
# Reshape of the legacy 3-postswap-container-restart-kill (C8) onto the kill-arc
# driver. CRASH identical (REAL killed-by-system-during-container-restart inject,
# service.go:4779 — POSTSWAP: binary swapped, migrations applied, flag pinned
# Phase=Resuming, DB UP); only the SCHEDULING swapped (fabricate → real
# register+schedule, 086) + the baseline (v2026.05.2 → base_sha). Contract preserved.
#
# A→B killed during the post-swap container restart → RED: flag (Phase=Resuming) +
# row in_progress (DB up; migrations applied; containers indeterminate). Recovery
# (./sb install) → Resuming one-shot LATCH (service.go:755) → recoveryRollback →
# rollback → exit 75; the death-during-resume becomes ONE rollback, NEVER a
# re-resume-to-completion. Terminal rolled_back with UPGRADE_DIED_DURING_RESUME;
# data restored from the snapshot.
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

upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

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

# ── RED: flag Phase=Resuming + row in_progress (POSTSWAP — DB is UP) ──
echo ""
echo "── verifying C8 RED state (flag Resuming; row in_progress; DB up) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || { echo "✗ expected flag file present after the kill" >&2; exit 1; }
assert_upgrade_row_state "$VM_NAME" "in_progress"
echo "  ✓ RED confirmed: flag (Phase=Resuming) + row in_progress (migrations applied; containers indeterminate)"

# ── recovery: ./sb install → Resuming one-shot latch → rollback (NEVER re-resume) ──
echo ""
echo "── recovery: ./sb install (Resuming latch → rollback) ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" || REC_RC=$?
echo "  recovery ./sb install exit: $REC_RC (0 or 75=rolled-back both OK)"

# ── convergence: ROLLBACK, never completion (the Resuming latch) ──
echo ""
echo "── latch-outcome convergence checks (ROLLBACK, not completion) ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
if [ "$FINAL_STATE" = "completed" ]; then
    echo "✗ state='completed' — a death-during-resume must NOT re-resume to step 11+12; the Resuming one-shot latch (service.go:755) must roll back (latch regressed?)" >&2
    exit 1
fi
# Principled terminal: rolled_back (the snapshot restore succeeds → healthy at A).
assert_upgrade_row_state "$VM_NAME" "rolled_back"
# The error names the latch code (ErrResumeDied) — the unattended operator's diagnostic surface.
assert_upgrade_row_error_matches "$VM_NAME" "UPGRADE_DIED_DURING_RESUME"
# Data restored intact from the snapshot — the resume's migrate was undone by rollback's restoreDatabase.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: postswap-container-restart-kill (death-during-resume → ONE rollback via the Resuming latch; row rolled_back with UPGRADE_DIED_DURING_RESUME, data intact)"
