#!/bin/bash
# Arc: rollback-kill  (STATBUS-071 §9(5) / doc-016 — 5b, CAT-A; C9) — DETERMINISTIC
#
# Reshape of the legacy 4-rollback-kill (C9) onto the kill-arc driver. CRASH path
# identical (REAL injects); only the SCHEDULING swapped (fabricate → real
# register+schedule) + baseline (v2026.05.2 → base_sha).
#
# DETERMINISTIC (architect-reconciled + VM-proven, run 27815639940): the legacy
# "both-outcomes" model is STALE. recoverFromFlag branches by FLAG PHASE — a
# binary-swap (C5) kill = a PreSwap flag → :945 recoveryRollback (service.go:2174)
# WRAPS d.rollback() (:2271 → :5461) → the FULL rollback pipeline → :5646
# KillHere(killed-by-system-during-builtin-rollback). restoreDatabase is a NO-OP for
# the PreSwap wedge (empty BackupPath → refuses) but d.rollback CONTINUES to :5646,
# so C9 fires DETERMINISTICALLY (exit 137). Outcome A (forward-recovery→completed) is
# DEAD — the :822 never-self-heal guard forbids a PreSwap self-heal-to-completed.
# So this asserts the SINGLE proven path:
#   1st dispatch (C5 binary-swap kill): exit 137 → PreSwap wedge.
#   2nd dispatch (recovery + C9 builtin-rollback): exit 137 → C9 fired (:5646 reached).
#   3rd dispatch (cleanup ./sb install): completes the partial rollback → rolled_back.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-rollback-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"

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

# _dump_rollback_kill_failure_diagnostics — STATBUS-155 rider (mirrors
# postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics): on ANY
# non-zero exit, pull B's own upgrade progress log + the daemon journal + its
# row state to STDERR before cleanup_vm reaps the VM, so a red run is
# self-sufficient without needing a kept VM. Best-effort throughout (|| true)
# — a diagnostics failure must never mask the real assertion error that
# triggered this trap.
_dump_rollback_kill_failure_diagnostics() {
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

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_rollback_kill_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: rollback-kill  (C9 — deterministic: PreSwap wedge → recoveryRollback → d.rollback → :5646 → C9)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

row_state()    { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
flag_present() { VM_EXEC bash -c "test -f ~/statbus/tmp/upgrade-in-progress.json && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }

# ── A: install + prepare; register; schedule daemon-down ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"

# ── 1st dispatch: C5 binary-swap kill → PreSwap wedge (exit 137) ──
echo ""
echo "── 1st dispatch: C5 binary-swap kill (PreSwap wedge) ──"
arc_install_dispatch_with_inject "killed-by-system-during-binary-swap"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ 1st dispatch exited $ARC_DISPATCH_RC (expected 137) — the C5 kill did not fire; no wedge" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ expected flag file present after the C5 kill" >&2; exit 1; }
echo "[OBSERVE] C5 wedge: exit 137, flag present (Phase=PreSwap)"

# ── 2nd dispatch: C9 builtin-rollback inject during recovery → fires DETERMINISTICALLY ──
echo ""
echo "── 2nd dispatch: recovery + C9 builtin-rollback kill (recoveryRollback→d.rollback→:5646) ──"
arc_install_dispatch_with_inject "killed-by-system-during-builtin-rollback"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ 2nd dispatch exited $ARC_DISPATCH_RC (expected 137) — C9 did NOT fire. A PreSwap wedge must route :945 recoveryRollback → d.rollback → :5646 (deterministic); a non-137 exit means that path regressed (e.g. recovery self-healed to completed, violating the :822 never-self-heal guard)" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ expected flag file present after the C9 kill (partial-rollback wedge)" >&2; exit 1; }
echo "[OBSERVE] C9 FIRED: exit 137, :5646 builtin-rollback reached, partial-rollback wedge (flag present)"

# ── 3rd dispatch: cleanup recovery → completes the partial rollback ──
echo ""
echo "── 3rd dispatch: ./sb install (no inject) → complete the rollback ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" || REC_RC=$?
echo "[OBSERVE] 3rd dispatch (cleanup) exit: $REC_RC (0 or 75=rolled-back both OK)"

# ── convergence: the deterministic terminal is rolled_back (NEVER completed) ──
echo ""
echo "── convergence checks (deterministic outcome-B) ──"
FINAL_STATE=$(row_state)
echo "[OBSERVE] final row state: $FINAL_STATE"
[ "$FINAL_STATE" != "completed" ] || { echo "✗ state='completed' — a PreSwap/C9 rollback must NOT self-heal to completed (:822 guard / never-self-heal)" >&2; exit 1; }
[ "$FINAL_STATE" = "rolled_back" ] || { echo "✗ expected terminal 'rolled_back' (the completed C9 rollback), got '$FINAL_STATE'" >&2; exit 1; }
echo "  ✓ rolled_back (C9 rollback completed by the 3rd dispatch)"
# The error names the PreSwap rollback reason (recoverFromFlag :955) — proves this
# was the binary-swap PreSwap path (interrupted before the binary-swap commit boundary).
assert_upgrade_row_error_matches "$VM_NAME" "pre-swap, before binary-swap commit boundary"
assert_flag_file_absent "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: rollback-kill (deterministic C9: PreSwap wedge → recoveryRollback→d.rollback→:5646 fires C9 [137]; 3rd dispatch completed the rollback → rolled_back; data intact)"
