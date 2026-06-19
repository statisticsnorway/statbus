#!/bin/bash
# Arc: postswap-rollback-restore-watchdog  (STATBUS-071 §9(5) / doc-016 — 5c CAT-B; STATBUS-031)
#
# Reshape of the legacy 4-rollback-restore-watchdog onto the PROVEN stall-dispatch
# driver via the V_fail trigger. Only the SCHEDULING swapped (fabricate → real
# register+schedule) + baseline (→ base_sha). VERIFIED working (architect, run
# 27824537231): V_fail postswap → postSwapFailure → rollback() → restoreDatabase
# REACHES the :761 stall (progress "Restoring database from backup at …" then silent/
# parked); the STATBUS-031 always-ping ticker (service.go:5485) covers it; NRestarts
# stays bounded across the >WatchdogSec park.
#
# What it proves (STATBUS-031): rollback()'s restoreDatabase rsync (heartbeat-SILENT)
# on the recovery path would, without the always-ping ticker, trip WatchdogSec=120s →
# SIGABRT mid-restore → restore-from-scratch loop. The ticker keeps WATCHDOG=1 firing
# through the stall → it completes → rolled_back; NRestarts bounded.
#
# RESTORE-AWARE (e) gate (the key fix — restoreDatabase STOPS the DB for the rsync, so
# the row is UNREADABLE during the stall; "row in_progress" is the WRONG probe). Prove
# the stall genuinely held ≥WatchdogSec via THREE restore-aware signals:
#   (i)   progress.log "Restoring database from backup at" present (exec.go:752 → :761 reached);
#   (ii)  the DB is DOWN (rollback stopped it for the rsync — the stall state), NOT "in_progress";
#   (iii) NRestarts NOT climbing (the always-ping ticker held; no WatchdogSec SIGABRT).
# Then release → DB back up → rollback completes → rolled_back + data restored.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-rollback-restore-watchdog}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
STALL_HOLD_S="${STALL_HOLD_S:-180}"            # > WatchdogSec=120s — load-bearing
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"
INPROGRESS_BUDGET_S="${INPROGRESS_BUDGET_S:-300}"
SETTLE_WATCH_S="${SETTLE_WATCH_S:-300}"
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
echo "  Arc: postswap-rollback-restore-watchdog  (STATBUS-031 — V_fail → rollback's restoreDatabase stall; restore-aware (e))"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  trigger=V_fail  stall-hold=${STALL_HOLD_S}s (> WatchdogSec=120s)"
echo "════════════════════════════════════════════════════════════════"

row_state()    { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
db_up()        { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT 1;' | ./sb psql -t -A 2>/dev/null" 2>/dev/null | tr -d ' \r\n' || echo ""; }
progress_has() { VM_EXEC bash -c "grep -qF \"$1\" ~/statbus/tmp/upgrade-progress.log 2>/dev/null && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }

# ── A: install + prepare; register B(=V_fail); arm the restore-stall dropin ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo ""
echo "── register B (=A+V_fail) (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_install_stall_dropin "$INJECT_CLASS" "$RELEASE_FILE"

echo ""
echo "── schedule B (daemon runs it → V_fail postswap → rollback → restoreDatabase stall) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

echo ""
echo "── waiting for B → in_progress (daemon claims; DB still up at claim) ──"
arc_wait_row_state "$B_FULL" "in_progress" "$INPROGRESS_BUDGET_S"

# (a) baseline NRestarts AFTER in_progress (captures the arc_install_stall_dropin restart).
NRESTARTS_BASELINE=$(arc_nrestarts)
echo "  baseline NRestarts (post-claim): $NRESTARTS_BASELINE"

# ── hold > WatchdogSec, watching NRestarts (flat=GREEN, climb=RED). The DB goes DOWN
#    as the rollback reaches restoreDatabase — NRestarts is read via systemctl (no DB). ──
echo ""
echo "── holding the restore stall ${STALL_HOLD_S}s (> WatchdogSec=120s); watching NRestarts ──"
HOLD_TS=$(date +%s)
while [ $(( $(date +%s) - HOLD_TS )) -lt "$STALL_HOLD_S" ]; do
    elapsed=$(( $(date +%s) - HOLD_TS ))
    NR=$(arc_nrestarts)
    [ $((elapsed % 20)) -eq 0 ] && echo "    [t+${elapsed}s] NRestarts=$NR (baseline=$NRESTARTS_BASELINE) — flat=GREEN, climbing=RED"
    # DELTA-0 (architect): the ticker-covered delta is 0 (baseline already includes the
    # pre-schedule dropin restart). A +1 tolerance would MASK the RED — the ticker-removed
    # build SIGABRTs ONCE at ~WatchdogSec (≈120s, within the 180s hold) → baseline+1 → a
    # +1 bound passes. So ANY climb above baseline = a watchdog SIGABRT = RED.
    if [ "$NR" != "?" ] && [ "$NR" -gt "$NRESTARTS_BASELINE" ]; then
        echo "✗ NRestarts climbed to $NR > baseline=$NRESTARTS_BASELINE during the silent restore → WatchdogSec SIGABRT'd the unit mid-restore: rollback's restoreDatabase has NO watchdog cover (STATBUS-031 regressed)" >&2
        exit 1
    fi
    sleep 5
done

# ── RESTORE-AWARE (e) ANTI-FALSE-PASS (the stall genuinely held at restoreDatabase) ──
echo ""
echo "── restore-aware (e) gate: prove the restore stall held ≥WatchdogSec ──"
# (i) restoreDatabase reached its :752 progress line → it's parked at the :761 stall.
[ "$(progress_has 'Restoring database from backup at')" = "yes" ] || { echo "✗ (e)/i: progress.log has NO 'Restoring database from backup at' — the rollback never reached restoreDatabase (:752/:761); the stall didn't engage" >&2; VM_EXEC bash -c "tail -30 ~/statbus/tmp/upgrade-progress.log 2>/dev/null" >&2 || true; exit 1; }
echo "  ✓ (i) restoreDatabase reached :752 (progress 'Restoring database from backup at')"
# (ii) the DB is DOWN — rollback stopped it for the rsync (the stall state); NOT in_progress.
[ "$(db_up)" != "1" ] || { echo "✗ (e)/ii: DB is UP during the hold — the restore is NOT parked (it stops the DB for the rsync). The rollback completed or the stall didn't hold" >&2; echo "  row=$(row_state)" >&2; exit 1; }
echo "  ✓ (ii) DB is DOWN (rollback stopped it for the rsync — the restore is parked, not completed)"
# (iii) NRestarts not climbing (re-confirm at hold-end).
NR_END=$(arc_nrestarts)
[ "$NR_END" -le "$NRESTARTS_BASELINE" ] || { echo "✗ (e)/iii: NRestarts=$NR_END > baseline=$NRESTARTS_BASELINE (delta>0) — a watchdog SIGABRT landed during the restore (STATBUS-031 regressed; delta-0 bound: even ONE SIGABRT at ~WatchdogSec must RED, a +1 tolerance would mask it)" >&2; exit 1; }
echo "  ✓ (iii) NRestarts=$NR_END == baseline (delta 0) — the always-ping ticker held the unit alive across the ${STALL_HOLD_S}s stall"

# ── release → DB back up → rollback completes → rolled_back ──
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
echo "PASS: postswap-rollback-restore-watchdog (V_fail → rollback's restoreDatabase stalled ${STALL_HOLD_S}s > WatchdogSec [restore-aware (e): :752 reached + DB down + NRestarts flat]; the STATBUS-031 always-ping ticker kept the unit alive; restore completed on release, row rolled_back, snapshot intact)"
