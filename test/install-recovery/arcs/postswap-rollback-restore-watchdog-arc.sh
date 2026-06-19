#!/bin/bash
# Arc: postswap-rollback-restore-watchdog  (STATBUS-071 §9(5)) — *** OBSERVATIONAL / DIAGNOSTIC ***
#
# CAT-B did not close: the delta-0 gate false-RED'd the GREEN build because the
# GREEN build has a DETERMINISTIC t+44s NRestarts +1 = the EXIT-42 BINARY-SWAP
# HANDOFF (service.go:4371 os.Exit(42); :164 "every healthy exit-42 handoff" bumps
# NRestarts). So GREEN = baseline+1, NOT baseline → delta-0 too strict. This
# observe-run GROUNDS the right gate (run is the oracle): it LOGS the full NRestarts
# TIMELINE (timestamped — see the t+44s handoff + whether it stays flat [GREEN] or
# climbs [RED at ~120s/~240s SIGABRTs]), the JOURNAL around the restart (confirm
# exit-42 handoff), a LONGER hold (≥260-300s), and whether the scenario reaches
# rolled_back (NEVER cleanly seen). PASS on any coherent terminal so the run
# completes and we read the markers.
#
# Fire on BOTH: the GREEN build (default base_sha → expect baseline+1 then flat →
# rolled_back) AND the RED build (base_sha=79375b9f9 red/031-rollback-watchdog [the
# SHA, NOT the branch name — the construct git-rev-parses it] → expect baseline+1 +
# SIGABRT climb). The two trajectories ground the ≤baseline+1 bound.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-rollback-restore-watchdog}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
HOLD_WATCH_S="${HOLD_WATCH_S:-300}"            # > WatchdogSec=120s, long enough to see a 2nd SIGABRT (~240s)
SETTLE_WATCH_S="${SETTLE_WATCH_S:-360}"
INPROGRESS_BUDGET_S="${INPROGRESS_BUDGET_S:-300}"
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
echo "  Arc: postswap-rollback-restore-watchdog  (OBSERVATIONAL — NRestarts timeline + t+44s cause + rolled_back?)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  trigger=V_fail  inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

row_state()  { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
db_up()      { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT 1;' | ./sb psql -t -A 2>/dev/null" 2>/dev/null | tr -d ' \r\n' || echo ""; }
progress_has(){ VM_EXEC bash -c "grep -qF \"$1\" ~/statbus/tmp/upgrade-progress.log 2>/dev/null && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }

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
echo "── schedule B (daemon runs it → swap [exit-42 handoff] → V_fail → rollback → restoreDatabase stall) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

echo ""
echo "── waiting for B → in_progress ──"
arc_wait_row_state "$B_FULL" "in_progress" "$INPROGRESS_BUDGET_S"
NRESTARTS_BASELINE=$(arc_nrestarts)
echo "[OBSERVE] baseline NRestarts (post-claim, PRE-swap-handoff): $NRESTARTS_BASELINE"

# ── HOLD-watch: log the NRestarts TIMELINE (t+44s handoff? flat? climbing?) ──
echo ""
echo "── HOLD-watch ${HOLD_WATCH_S}s — NRestarts timeline (expect: +1 at ~t+44s = exit-42 handoff [GREEN flat after]; RED climbs at ~120s/~240s) ──"
HOLD_TS=$(date +%s); SAW_RESTORE_START=0
while [ $(( $(date +%s) - HOLD_TS )) -lt "$HOLD_WATCH_S" ]; do
    elapsed=$(( $(date +%s) - HOLD_TS ))
    NR=$(arc_nrestarts); ST=$(row_state); DB=$(db_up)
    # RESTORE-START timestamp — calibrates the eventual ASSERTING hold: the RED's
    # SIGABRT fires at restore-start + WatchdogSec(120s), NOT hold-start. asserting
    # hold = restore-start + WatchdogSec + ~60s margin ≥ 240s.
    if [ "$SAW_RESTORE_START" = "0" ] && [ "$(progress_has 'Restoring database from backup at')" = "yes" ]; then
        SAW_RESTORE_START=1
        echo "[OBSERVE] *** RESTORE-START at t+${elapsed}s (progress :752 'Restoring database from backup at') — asserting-hold ≥ restore-start + WatchdogSec(120) + 60 ***"
    fi
    [ $((elapsed % 15)) -eq 0 ] && echo "[OBSERVE]   [t+${elapsed}s] NRestarts=$NR (baseline=$NRESTARTS_BASELINE) row=$ST db_up=${DB:-DOWN}"
    sleep 5
done
echo "[OBSERVE] restoreDatabase reached (:752 'Restoring database from backup at'): $(progress_has 'Restoring database from backup at')"
DBH=$(db_up); echo "[OBSERVE] db_up at hold-end (DOWN ⟹ restore parked): ${DBH:-DOWN}"
echo "[OBSERVE-J] journal around the restarts (confirm exit-42 handoff at ~t+44s + any watchdog SIGABRT):"
VM_EXEC bash -c "journalctl --user -u $ARC_UPGRADE_UNIT --no-pager -n 120 2>/dev/null | grep -iE 'exit 42|handoff|watchdog|abort|SIGABRT|Stopping|Started|restore|rollback' | tail -30" 2>/dev/null | sed 's/^/[OBSERVE-J]   /' || echo "[OBSERVE-J]   (journal unavailable)"

# ── release → does it reach rolled_back? (never cleanly seen) ──
echo ""
echo "── releasing the stall (rm $RELEASE_FILE); watching for terminal (up to ${SETTLE_WATCH_S}s) ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE"
START_TS=$(date +%s); FINAL=""
while [ $(( $(date +%s) - START_TS )) -lt "$SETTLE_WATCH_S" ]; do
    elapsed=$(( $(date +%s) - START_TS ))
    NR=$(arc_nrestarts); ST=$(row_state)
    [ $((elapsed % 15)) -eq 0 ] && echo "[OBSERVE]   [release+${elapsed}s] NRestarts=$NR row=$ST"
    case "$ST" in
        completed|failed|rolled_back) FINAL="$ST"; echo "[OBSERVE] row reached terminal '$ST' (release+${elapsed}s)"; break ;;
    esac
    sleep 5
done
[ -n "$FINAL" ] || echo "[OBSERVE] row did NOT reach a terminal within ${SETTLE_WATCH_S}s (last=$(row_state))"

echo ""
echo "── FINAL OBSERVATIONS ──"
echo "[OBSERVE] FINAL row state: $(row_state)"
echo "[OBSERVE] FINAL NRestarts: $(arc_nrestarts) (baseline=$NRESTARTS_BASELINE)"
echo "[OBSERVE] row error: $(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT error FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d '\r' || echo '?')"

echo ""
echo "OBSERVATIONAL PASS: rollback-restore diagnostic — grep [OBSERVE]/[OBSERVE-J] for: the NRestarts timeline (t+44s exit-42 handoff = +1; GREEN flat after vs RED SIGABRT climb), whether it reaches rolled_back after the longer hold, and the journal restart causes. Grounds the ≤baseline+1 bound."
