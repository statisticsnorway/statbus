#!/bin/bash
# Arc: postswap-rollback-restore-watchdog  (STATBUS-071 §9(5)) — *** OBSERVATIONAL / DIAGNOSTIC ***
#
# The V_fail rollback-restore went RED: the (e) gate caught the restore never stalling
# at :761 (the upgrade went terminal during the hold). Code-grounded: restoreDatabase
# (exec.go:739-742) returns at :741 if backupPath=="" ("nothing to restore; the DB was
# never mutated") BEFORE the StallHere at :761. So a bare-RAISE V_fail likely rolls back
# HOLLOW (no snapshot to restore → :741 no-op → no stall). The run is the oracle; this
# OBSERVES (logs, does NOT assert the stall) so the architect can distinguish:
#   (a) backupPath EMPTY → :741 no-op (progress: "No snapshot was recorded …") → V_fail's
#       rollback is hollow → fix the TRIGGER (a migration that mutates + finalizes a
#       snapshot, or a kill-DURING-restore variant).
#   (b) backupPath SET + progress "Restoring database from backup at …" but no park →
#       :761 reached but the stall env didn't arm → fix the ARM (rollback-context env).
# PASS on any coherent terminal so the run completes and we read the markers.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-rollback-restore-watchdog}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-600}"
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
echo "  Arc: postswap-rollback-restore-watchdog  (OBSERVATIONAL — does V_fail's rollback reach restoreDatabase :761?)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  trigger=V_fail  inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

row_state()  { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
row_backup() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT backup_path FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
flag_dump()  { VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null" 2>/dev/null || echo "(no flag file)"; }

# ── A: install + prepare; register B(=V_fail); arm the restore-stall dropin ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
NRESTARTS_BASELINE=$(arc_nrestarts)
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

echo ""
echo "── register B (=A+V_fail) (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_install_stall_dropin "$INJECT_CLASS" "$RELEASE_FILE"
echo "[OBSERVE] daemon STATBUS_INJECT_AT (Environment): $(VM_EXEC systemctl --user show "$ARC_UPGRADE_UNIT" -p Environment 2>/dev/null | tr -d '\r')"
echo "[OBSERVE] release file armed: $(VM_EXEC bash -c "test -f $RELEASE_FILE && echo yes || echo no" 2>/dev/null | tr -d ' \r\n')"

echo ""
echo "── schedule B (V_fail postswap → postSwapFailure → rollback → restoreDatabase?) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

# ── OBSERVE the upgrade run to terminal (log row + NRestarts + flag backup_path + timing) ──
echo ""
echo "── OBSERVE the run (logging, NOT asserting the stall) ──"
START_TS=$(date +%s); SAW_INPROGRESS=0
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    [ "$elapsed" -lt "$UPGRADE_BUDGET_S" ] || break
    ST=$(row_state); NR=$(arc_nrestarts)
    [ "$ST" = "in_progress" ] && SAW_INPROGRESS=1
    if [ $((elapsed % 15)) -eq 0 ]; then
        echo "[OBSERVE]   [t+${elapsed}s] row=$ST NRestarts=$NR flag_backup=$(VM_EXEC bash -c "grep -o '\"backup_path\"[^,}]*' ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(no flag)'" 2>/dev/null | tr -d '\r')"
    fi
    case "$ST" in
        completed|failed|rolled_back) echo "[OBSERVE] row reached terminal '$ST' (t+${elapsed}s)"; break ;;
    esac
    sleep 5
done
[ "$SAW_INPROGRESS" = "1" ] || echo "[OBSERVE] ⚠ never saw in_progress — the daemon may not have claimed B (a different problem)"

# ── THE DISCRIMINATOR: backup_path column + the :740-vs-:752 progress markers ──
echo ""
echo "── DISCRIMINATOR OBSERVATIONS ──"
echo "[OBSERVE] FINAL row state: $(row_state)"
BP=$(row_backup); echo "[OBSERVE] row backup_path COLUMN: ${BP:-(EMPTY)}   ← EMPTY ⟹ (a) :741 no-op (hollow rollback); SET ⟹ (b) reached restoreDatabase"
echo "[OBSERVE] row error: $(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT error FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d '\r' || echo '?')"
echo "[OBSERVE] release file still present (stall would hold it): $(VM_EXEC bash -c "test -f $RELEASE_FILE && echo yes || echo no" 2>/dev/null | tr -d ' \r\n')"
echo "[OBSERVE] flag JSON (final):"; flag_dump | sed 's/^/[OBSERVE]   /'
echo ""
echo "[OBSERVE-P] restoreDatabase progress markers (~/statbus/tmp/upgrade-progress.log):"
echo "[OBSERVE-P]   :741 no-op (a) → 'No snapshot was recorded' ; :752 reached (b) → 'Restoring database from backup at'"
VM_EXEC bash -c "grep -nE 'No snapshot was recorded|Restoring database from backup at|rollback|restoreDatabase' ~/statbus/tmp/upgrade-progress.log 2>/dev/null | tail -20" 2>/dev/null | sed 's/^/[OBSERVE-P]   /' || echo "[OBSERVE-P]   (progress log unavailable)"
echo ""
echo "[OBSERVE-J] daemon journal (rollback path, tail):"
VM_EXEC bash -c "journalctl --user -u $ARC_UPGRADE_UNIT --no-pager -n 80 2>/dev/null | grep -iE 'rollback|restore|snapshot|backup|migrat|fail' | tail -25" 2>/dev/null | sed 's/^/[OBSERVE-J]   /' || echo "[OBSERVE-J]   (journal unavailable)"

# Best-effort: release any held stall so cleanup is clean.
VM_EXEC bash -c "rm -f $RELEASE_FILE" 2>/dev/null || true

echo ""
echo "OBSERVATIONAL PASS: rollback-restore diagnostic — grep [OBSERVE]/[OBSERVE-P] for the discriminator: backup_path EMPTY + ':741 No snapshot was recorded' ⟹ (a) hollow rollback (fix the trigger); backup_path SET + ':752 Restoring database from backup at' (no park) ⟹ (b) :761 reached but stall env didn't arm. The architect's call on the fix follows from this."
