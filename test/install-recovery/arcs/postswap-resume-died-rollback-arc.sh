#!/bin/bash
# Arc: postswap-resume-died-rollback  (STATBUS-071 §9(5) / doc-016 — 5c CAT-B; #29 latch)
#
# Reshape of the legacy 3-postswap-resume-died-rollback onto a NEW 4th sub-variant:
# the KILL-via-dropin (daemon-RUN + a dropin KILL, distinct from 5a/5b's daemon-DOWN
# inline-kill AND from the CAT-B stall). Only the SCHEDULING swapped (fabricate →
# real register+schedule) + baseline (v2026.05.2 → base_sha).
#
# What it proves (#29 one-shot Resuming latch): a death DURING the post-swap resume
# becomes ONE rollback, never a retry loop. resumePostSwap stamps Phase=Resuming the
# instant it commits to applyPostSwap on the new binary; if that process then dies,
# the next recoverFromFlag sees Resuming and ROLLS BACK (never re-resumes). LOAD-
# BEARING = NRestarts BOUNDED (~kill restart + rollback restart, then stable), NOT
# climbing (the inverse of the 40h NO/rune wedge).
#
# Two runs (reuses killed-by-system-during-container-restart, AFTER the Resuming stamp):
#   RUN 1 — inline ./sb install + the kill (daemon-DOWN dispatch) → killed mid-
#           applyPostSwap → flag PostSwap + row in_progress (the resume precondition).
#   RUN 2 — arc_install_kill_dropin pins the SAME kill into the UNIT env + starts it
#           → recoverFromFlag PostSwap → resumePostSwap stamps Resuming → applyPostSwap
#           → migrate runs (mutates DB) → docker-up KILL (137) → systemd restarts →
#           recoverFromFlag Resuming → recoveryRollback → rollback (undoes the migrate)
#           → rolled_back + UPGRADE_DIED_DURING_RESUME → settle.
# Then assert ONE rollback (rolled_back + error + data restored + flag absent) + the
# NO-LOOP proof (remove the dropin → NRestarts bounded, not climbing).
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-resume-died-rollback}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
INJECT_RESTART_S="${INJECT_RESTART_S:-10}"
SETTLE_WATCH_S="${SETTLE_WATCH_S:-240}"
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

_arc_cleanup() { arc_remove_dropin; }
trap 'rc=$?; _arc_cleanup; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-resume-died-rollback  (#29 latch — death-during-resume → ONE rollback, no loop)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS} (kill-via-dropin)"
echo "════════════════════════════════════════════════════════════════"

row_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare; baseline NRestarts; register; schedule daemon-down ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
NRESTARTS_BASELINE=$(arc_nrestarts)
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"

# ── RUN 1: inline kill mid-applyPostSwap → PostSwap wedge (resume precondition) ──
echo ""
echo "── RUN 1: inline ./sb install + kill mid-applyPostSwap (establishes the resume state) ──"
arc_install_dispatch_with_inject "$INJECT_CLASS"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ RUN 1 exited $ARC_DISPATCH_RC (expected 137) — the kill did not fire; no resume state" >&2; exit 1; }
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || { echo "✗ expected flag file present after the RUN 1 kill" >&2; exit 1; }
assert_upgrade_row_state "$VM_NAME" "in_progress"
echo "  ✓ resume precondition: flag pinned PostSwap, row in_progress"

# ── RUN 2: kill-via-dropin on the UNIT → resume stamps Resuming, then dies ──
arc_install_kill_dropin "$INJECT_CLASS" "$INJECT_RESTART_S"

# ── watch for the rollback to land + NRestarts to settle (ONE rollback, no loop) ──
echo ""
echo "── watching for rollback + settle (up to ${SETTLE_WATCH_S}s) ──"
START_TS=$(date +%s)
FINAL_STATE=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    [ "$elapsed" -lt "$SETTLE_WATCH_S" ] || break
    NR=$(arc_nrestarts)
    STATE=$(row_state)
    [ $((elapsed % 20)) -eq 0 ] && echo "    [t+${elapsed}s] NRestarts=$NR row=$STATE (baseline=$NRESTARTS_BASELINE)"
    case "$STATE" in
        rolled_back|failed) FINAL_STATE="$STATE"; echo "  ✓ row reached terminal '$STATE' (t+${elapsed}s)"; break ;;
        completed) echo "✗ row reached 'completed' — the death-during-resume must NOT succeed (the latch must roll back)" >&2; exit 1 ;;
    esac
    sleep 5
done
if [ -z "$FINAL_STATE" ]; then
    echo "✗ row did not reach a terminal state within ${SETTLE_WATCH_S}s — the Resuming latch did not roll back (a stuck in_progress + climbing NRestarts here is the OLD retry-loop wedge)" >&2
    VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql" >&2 || true
    VM_EXEC bash -c "systemctl --user status $ARC_UPGRADE_UNIT --no-pager 2>&1 | head -20" >&2 || true
    exit 1
fi

# ── latch-contract assertions (LOAD-BEARING) ──
echo ""
echo "── latch-contract checks (LOAD-BEARING) ──"
if [ "$FINAL_STATE" = "failed" ]; then
    echo "  ⚠ terminal 'failed' (degraded) — the latch fired but the rollback's restore ALSO failed; investigate restoreDatabase"
else
    assert_upgrade_row_state "$VM_NAME" "rolled_back"
fi
assert_upgrade_row_error_matches "$VM_NAME" "UPGRADE_DIED_DURING_RESUME"
assert_flag_file_absent "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# ── NO-LOOP proof: remove the inject dropin → the unit must settle bounded ──
echo ""
echo "── NO-LOOP proof: remove the inject dropin; confirm the unit settles (not looping) ──"
arc_remove_dropin
assert_systemd_restart_counter_bounded "$VM_NAME" "$ARC_UPGRADE_UNIT" "$((NRESTARTS_BASELINE + 5))"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: postswap-resume-died-rollback (death-during-resume → ONE rollback via the Resuming latch; rolled_back + UPGRADE_DIED_DURING_RESUME, snapshot restored, NRestarts bounded — no loop)"
