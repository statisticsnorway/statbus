#!/bin/bash
# Arc: postswap-rollback-restore-watchdog  (STATBUS-071 §9(5) / doc-016 — 5c CAT-B; STATBUS-031)
#
# Reshape of the legacy 4-rollback-restore-watchdog onto the PROVEN stall-dispatch
# driver via the V_fail trigger (architect re-scope — the legacy's kill-via-dropin
# trigger was self-heal-blocked; V_fail is self-heal-DEFEATING, proven by the green
# failing arc, and POSTSWAP so restoreDatabase has a real backup_path to restore).
# Only the SCHEDULING swapped (fabricate → real register+schedule) + baseline (→ base_sha).
#
# What it proves (STATBUS-031): rollback()'s restoreDatabase rsync (onAdvance=nil →
# bypasses the heartbeat) on the recovery path has NO other WATCHDOG=1 source. A slow
# restore (>WatchdogSec=120s) would, without a cover, SIGABRT the unit mid-restore →
# restore-from-scratch loop. STATBUS-031 wraps rollback() in an always-ping ticker →
# a slow restore keeps feeding WATCHDOG=1 → it completes → rolled_back; NRestarts bounded.
#
# Flow (V_fail → rollback → restore-stall; the C15 stall template, terminal=rolled_back):
#   arc_prepare_box → register B(=A+V_fail) → arc_install_stall_dropin restore-db-stall-
#   watchdog (default "wait" restart → daemon carries the stall env) → schedule B →
#   daemon runs executeUpgrade → backup → swap → applyPostSwap migrate=V_fail FAILS →
#   postSwapFailure → rollback() → restoreDatabase PARKS at the stall (exec.go:761) →
#   hold > WatchdogSec (NRestarts must stay bounded — the always-ping ticker) → release
#   → rsync completes → rollback completes → rolled_back; data restored from the snapshot.
#
# Must-adds (proven): (c) arc_install_stall_dropin RESTARTS the unit (env in the daemon
# process); (e) after the hold assert the row is STILL in_progress (restore held
# ≥WatchdogSec) before NRestarts/release; (a) NRestarts baseline AFTER in_progress.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-rollback-restore-watchdog}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
STALL_HOLD_S="${STALL_HOLD_S:-180}"            # > WatchdogSec=120s — load-bearing
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"
INPROGRESS_BUDGET_S="${INPROGRESS_BUDGET_S:-300}"
SETTLE_WATCH_S="${SETTLE_WATCH_S:-240}"
INJECT_CLASS="restore-db-stall-watchdog"
RELEASE_FILE="/tmp/arc-restore-stall-release"

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

_arc_cleanup() {
    VM_EXEC bash -c "rm -f $RELEASE_FILE 2>/dev/null; rm -f ~/.config/systemd/user/${ARC_UPGRADE_UNIT}.d/inject.conf 2>/dev/null; systemctl --user daemon-reload 2>/dev/null" 2>/dev/null || true
}
trap 'rc=$?; _arc_cleanup; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-rollback-restore-watchdog  (STATBUS-031 — always-ping ticker covers rollback's restoreDatabase)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  trigger=V_fail  stall-hold=${STALL_HOLD_S}s (> WatchdogSec=120s)"
echo "════════════════════════════════════════════════════════════════"

row_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare; baseline NRestarts; register B(=V_fail) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo ""
echo "── register B (=A+V_fail) (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

# ── (c) arm the restore stall via dropin + RESTART the unit (BEFORE scheduling) ──
arc_install_stall_dropin "$INJECT_CLASS" "$RELEASE_FILE"

echo ""
echo "── schedule B (daemon runs it → V_fail postswap → rollback → restoreDatabase stall) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

echo ""
echo "── waiting for B → in_progress (daemon claims; V_fail → rollback reaches restoreDatabase) ──"
arc_wait_row_state "$B_FULL" "in_progress" "$INPROGRESS_BUDGET_S"

# (a) baseline NRestarts AFTER in_progress (post the dispatch reset-failed, service.go:3926).
NRESTARTS_BASELINE=$(arc_nrestarts)
echo "  baseline NRestarts (post-dispatch-reset): $NRESTARTS_BASELINE"

# ── hold the restore stall > WatchdogSec, watching NRestarts (flat=GREEN, climb=RED) ──
echo ""
echo "── holding the restore stall ${STALL_HOLD_S}s (> WatchdogSec=120s); watching NRestarts ──"
HOLD_TS=$(date +%s)
while [ $(( $(date +%s) - HOLD_TS )) -lt "$STALL_HOLD_S" ]; do
    elapsed=$(( $(date +%s) - HOLD_TS ))
    NR=$(arc_nrestarts)
    [ $((elapsed % 20)) -eq 0 ] && echo "    [t+${elapsed}s] NRestarts=$NR (baseline=$NRESTARTS_BASELINE) — flat=GREEN, climbing=RED"
    if [ "$NR" != "?" ] && [ "$NR" -gt "$((NRESTARTS_BASELINE + 1))" ]; then
        echo "✗ NRestarts climbed to $NR during the silent restore (baseline=$NRESTARTS_BASELINE) → WatchdogSec SIGABRT'd the unit mid-restore: rollback's restoreDatabase has NO watchdog cover (STATBUS-031 regressed)" >&2
        exit 1
    fi
    sleep 5
done
echo "  ✓ NRestarts stayed bounded through the ${STALL_HOLD_S}s silent restore — the always-ping ticker held the unit alive"

# (e) ANTI-FALSE-PASS: the restore MUST still be holding (row in_progress) — else it
# completed too fast and the NRestarts-bounded proof is vacuous.
ST_AFTER_HOLD=$(row_state)
[ "$ST_AFTER_HOLD" = "in_progress" ] || { echo "✗ ANTI-FALSE-PASS: row is '$ST_AFTER_HOLD' after the ${STALL_HOLD_S}s hold (expected in_progress) — the restore did NOT hold past WatchdogSec (V_fail/rollback didn't reach restoreDatabase, or the stall didn't arm); NRestarts-bounded would be vacuous" >&2; exit 1; }
echo "  ✓ row STILL in_progress after ${STALL_HOLD_S}s — the restoreDatabase stall genuinely held past WatchdogSec"

# ── release → the rsync proceeds → the rollback completes ──
echo ""
echo "── releasing the stall (rm $RELEASE_FILE); watching for the rollback to land (up to ${SETTLE_WATCH_S}s) ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE"
START_TS=$(date +%s); FINAL_STATE=""
while [ $(( $(date +%s) - START_TS )) -lt "$SETTLE_WATCH_S" ]; do
    elapsed=$(( $(date +%s) - START_TS ))
    STATE=$(row_state)
    [ $((elapsed % 20)) -eq 0 ] && echo "    [t+${elapsed}s] row=$STATE"
    case "$STATE" in
        rolled_back|failed) FINAL_STATE="$STATE"; echo "  ✓ row reached terminal '$STATE' (t+${elapsed}s)" ; break ;;
        completed) echo "✗ row reached 'completed' — a V_fail must roll back, not forward-succeed" >&2; exit 1 ;;
    esac
    sleep 5
done
[ -n "$FINAL_STATE" ] || { echo "✗ row did not reach a terminal within ${SETTLE_WATCH_S}s after releasing the stall" >&2; VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql" >&2 || true; exit 1; }

# ── GREEN-contract assertions (LOAD-BEARING) ──
echo ""
echo "── GREEN-contract checks (LOAD-BEARING) ──"
if [ "$FINAL_STATE" = "failed" ]; then
    echo "  ⚠ terminal 'failed' (degraded) — the rollback's restore ALSO failed; investigate restoreDatabase, but the watchdog cover still held (NRestarts bounded above)"
else
    assert_upgrade_row_state "$VM_NAME" "rolled_back"
fi
assert_flag_file_absent "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_systemd_restart_counter_bounded "$VM_NAME" "$ARC_UPGRADE_UNIT" "$((NRESTARTS_BASELINE + 3))"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: postswap-rollback-restore-watchdog (V_fail → rollback's restoreDatabase stalled ${STALL_HOLD_S}s > WatchdogSec; the STATBUS-031 always-ping ticker kept the unit alive — NRestarts bounded — restore completed on release, row rolled_back, snapshot intact)"
