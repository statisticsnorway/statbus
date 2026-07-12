#!/bin/bash
# Arc: postswap-rollback-restore-watchdog  (STATBUS-071 §9(5); the former STATBUS-031)
#
# WHAT THIS PROVES — the rollback-restore watchdog COVER HOLDS.
# rollback()'s database restore (restoreDatabase's whole-volume rsync) is
# heartbeat-SILENT and DB-size-scaled: on Norway's 32 GB it runs far longer than
# systemd's WatchdogSec=120s. Without a cover, that silence is read as a hang →
# the unit is SIGABRT'd mid-restore → the next boot restores from scratch → SIGABRT
# again → an indefinite restore loop on the recovery path itself (the rune class,
# now on the undo). The shipped fix (STATBUS-031, commit a8279ed83) wraps rollback()
# in the always-ping WATCHDOG=1 ticker so a slow-but-progressing restore is NOT
# killed. This arc drives a REAL rollback (A→B=V_fail → executeUpgrade rolls back),
# STALLS the restore past WatchdogSec via the product's restore-db-stall inject, and
# ASSERTS the cover: NRestarts stays FROZEN through the stall (no watchdog SIGABRT),
# then on release the box reaches 'rolled_back' with a byte-identical clean slate.
#
# THE NRestarts BOUND (grounded by the earlier observational run of this arc).
# There is ONE legitimate NRestarts bump before the restore even starts: the
# exit-42 binary-swap handoff (service.go os.Exit(42) → systemd restart; "every
# healthy exit-42 handoff bumps NRestarts"), at ~t+44s. So at restore-start
# NRestarts = baseline+1. The cover-holds assertion is therefore not "== baseline"
# but "FROZEN at the restore-start value across a hold that outlasts WatchdogSec":
# a GREEN (covered) build holds flat; a RED (ticker-removed) build CLIMBS as the
# SIGABRT fires at restore-start + 120s, + 240s, … . We capture the restore-start
# value live (no hardcoded +1) and assert it never climbs while the restore is
# parked. After release, one further bump is legitimate — the clean rollback's own
# terminal os.Exit → systemd restart — so the post-terminal bound is start+1.
#
# RECONCILIATION with what shipped SINCE this arc was drafted (all confined to the
# RED/loop path this cover PREVENTS — none change the GREEN terminal):
#   • Budget hoist (cc660280f): counts recovery_attempts at the recovery-pass guard.
#     The GREEN path here is executeUpgrade's OWN deferred rollback (not a
#     recoverFromFlag recovery pass), so the guard never fires and recovery_attempts
#     stays 0 — this arc asserts the terminal + NRestarts, not the budget counter.
#   • STATBUS-134 (rollback pair-terminal) + STATBUS-136 (abort-terminal DB-start):
#     both act only when the restore is repeatedly SIGABRT'd into a mid-rollback
#     crash loop (the RED). With the cover HOLDING there is no loop, so neither
#     fires; the terminal stays 'rolled_back'.
#
# RED-DELTA (why this is a cover-HOLDS proof, not a RED run). The stale RED build
# red/031-rollback-watchdog@79375b9f9 proved, THEN, that removing the ticker made
# the restore stall exceed WatchdogSec → SIGABRT → NRestarts climb → restore-loop
# forever. That branch also predates the V_fail re-scope and 134/136, so its
# behavior has MOVED: a ticker-removed build today would SIGABRT mid-restore, and
# after two consecutive mid-rollback deaths 134's (rollback,rollback) pair-terminal
# would fire → 'failed' (restore-broke, human stop), 136 landing that terminal —
# a degraded terminal, not an infinite loop. Re-validating that RED is a separate
# one-off (a ticker-removed variant of HEAD, expecting restore-broke); it is NOT
# this arc's job. This arc asserts the shipped cover HOLDS: no climb, clean
# rolled_back. The frozen-NRestarts assertion is exactly the discriminator that
# would catch a future regression that removed or broke the cover.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-rollback-restore-watchdog}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INPROGRESS_BUDGET_S="${INPROGRESS_BUDGET_S:-300}"
# Time to see the restore stall site reached after the row is in_progress (swap +
# migrate V_fail + rollback-to-restore).
RESTORE_START_BUDGET_S="${RESTORE_START_BUDGET_S:-300}"
# The cover-holds hold, timed from RESTORE-START (not arc start): must outlast
# WatchdogSec(120s) with margin for a would-be SECOND SIGABRT (~240s) so a broken
# cover is unambiguously caught as a climb.
HOLD_AFTER_STALL_S="${HOLD_AFTER_STALL_S:-240}"
# After releasing the stall, time for the restore to finish + rollback to write
# 'rolled_back'.
SETTLE_WATCH_S="${SETTLE_WATCH_S:-360}"
INJECT_CLASS="restore-db-stall-watchdog"
RELEASE_FILE="/tmp/arc-restore-stall-release"
RESTORE_MARKER="Restoring database from backup at"

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

# _dump_rollback_restore_watchdog_failure_diagnostics — STATBUS-155 rider
# (mirrors postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics):
# on ANY non-zero exit, pull B's own upgrade progress log + the daemon journal
# + its row state to STDERR BEFORE _arc_cleanup removes the release marker /
# inject drop-in and cleanup_vm reaps the VM, so a red run is self-sufficient
# without needing a kept VM. Best-effort throughout (|| true) — a diagnostics
# failure must never mask the real assertion error that triggered this trap.
_dump_rollback_restore_watchdog_failure_diagnostics() {
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
    echo "── daemon journal ($ARC_UPGRADE_UNIT, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u $ARC_UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit (B's row, commit_sha = ${B_FULL:-?}) ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(recovery_parked_reason,''), error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_rollback_restore_watchdog_failure_diagnostics; fi; _arc_cleanup; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-rollback-restore-watchdog  (ASSERTING — cover HOLDS → rolled_back, NRestarts frozen through the restore stall)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  trigger=V_fail  inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

row_state()   { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
db_up()       { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT 1;' | ./sb psql -t -A 2>/dev/null" 2>/dev/null | tr -d ' \r\n' || echo ""; }
progress_has(){ VM_EXEC bash -c "grep -qF \"$1\" ~/statbus/tmp/upgrade-progress.log 2>/dev/null && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
# journal_watchdog_kills — count systemd WATCHDOG-TIMEOUT kills of the upgrade unit
# (the exact RED signature: silence > WatchdogSec → systemd aborts the process).
# The healthy exit-42 handoff does NOT log this line, so a nonzero count is a real
# watchdog kill = the cover FAILED.
journal_watchdog_kills() {
    VM_EXEC bash -c "journalctl --user -u $ARC_UPGRADE_UNIT --no-pager 2>/dev/null | grep -ciE 'watchdog timeout' || true" 2>/dev/null | tr -d ' \r\n' || echo "0"
}

# ── A: install + prepare; capture the clean-slate baseline; register B(=V_fail) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo "── capturing baseline clean-slate fingerprint (post-A) — the rollback must restore THIS byte-for-byte ──"
BASELINE_FP=$(capture_db_fingerprint baseline)
echo "  baseline fingerprint: $BASELINE_FP"

echo ""
echo "── register B (=A+V_fail) (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

# Arm the restore-stall inject in the daemon process (restart-for-env), BEFORE schedule.
arc_install_stall_dropin "$INJECT_CLASS" "$RELEASE_FILE"

echo ""
echo "── schedule B (daemon runs it → swap [exit-42 handoff] → V_fail → rollback → restoreDatabase STALLS) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

echo ""
echo "── waiting for B → in_progress ──"
arc_wait_row_state "$B_FULL" "in_progress" "$INPROGRESS_BUDGET_S"
NR_BASELINE=$(arc_nrestarts)
echo "[OBSERVE] baseline NRestarts (post-claim, PRE-swap-handoff): $NR_BASELINE"

# ── wait for the restore stall site to be REACHED (rollback began, restore parked) ──
echo ""
echo "── waiting for restore-start ('${RESTORE_MARKER}') — the rollback reached restoreDatabase and the inject parked it ──"
RS_TS=$(date +%s)
while true; do
    if [ "$(progress_has "$RESTORE_MARKER")" = "yes" ]; then break; fi
    ST=$(row_state)
    case "$ST" in
        completed|rolled_back|failed)
            echo "✗ row reached terminal '$ST' before the restore stall engaged — the V_fail rollback did not park at restoreDatabase (inject not armed?)" >&2
            exit 1 ;;
    esac
    if [ $(( $(date +%s) - RS_TS )) -ge "$RESTORE_START_BUDGET_S" ]; then
        echo "✗ restore-start not observed within ${RESTORE_START_BUDGET_S}s (last row='$ST') — the rollback never reached restoreDatabase" >&2
        VM_EXEC bash -c "cd ~/statbus && tail -40 tmp/upgrade-progress.log 2>/dev/null" >&2 || true
        exit 1
    fi
    sleep 5
done
NR_STALL=$(arc_nrestarts)
echo "[OBSERVE] restore-start reached; NRestarts at stall = $NR_STALL (baseline+exit42-handoff; expect baseline+1). db_up=$(db_up | sed 's/^$/DOWN/')"

# ── ASSERT: the cover HOLDS — NRestarts FROZEN across a hold that outlasts WatchdogSec ──
echo ""
echo "── cover-holds hold ${HOLD_AFTER_STALL_S}s from restore-start (stall ARMED; assert NRestarts never climbs above $NR_STALL) ──"
HOLD_TS=$(date +%s)
while [ $(( $(date +%s) - HOLD_TS )) -lt "$HOLD_AFTER_STALL_S" ]; do
    elapsed=$(( $(date +%s) - HOLD_TS ))
    NR=$(arc_nrestarts)
    [ $((elapsed % 15)) -eq 0 ] && echo "[OBSERVE]   [stall+${elapsed}s] NRestarts=$NR (stall-baseline=$NR_STALL) row=$(row_state) db_up=$(db_up | sed 's/^$/DOWN/')"
    # THE anti-watchdog-kill assertion: any climb above the restore-start value is a
    # SIGABRT-restart = the cover failed (this is precisely the RED trajectory).
    if [ "$NR" != "?" ] && [ "$NR_STALL" != "?" ] && [ "$NR" -gt "$NR_STALL" ]; then
        echo "✗ COVER FAILED: NRestarts climbed $NR_STALL → $NR while the restore was parked — the watchdog SIGABRT'd a progressing restore (the STATBUS-031 RED trajectory)." >&2
        echo "  journal (watchdog/abort markers):" >&2
        VM_EXEC bash -c "journalctl --user -u $ARC_UPGRADE_UNIT --no-pager -n 60 2>/dev/null | grep -iE 'watchdog|abort|SIGABRT|Stopping|Started' | tail -20" >&2 || true
        exit 1
    fi
    sleep 5
done
NR_HOLD_END=$(arc_nrestarts)
echo "[OBSERVE] hold complete: NRestarts=$NR_HOLD_END (stall-baseline=$NR_STALL)"

# Frozen: exactly equal to the restore-start value (no bumps at all while parked).
[ "$NR_HOLD_END" = "$NR_STALL" ] || {
    echo "✗ COVER FAILED: NRestarts moved $NR_STALL → $NR_HOLD_END across the parked-restore hold — expected FROZEN (the always-ping ticker keeps WATCHDOG=1 through the silent restore)." >&2
    exit 1
}
echo "  ✓ NRestarts FROZEN at $NR_STALL through ${HOLD_AFTER_STALL_S}s of parked restore (> WatchdogSec=120s) — the cover held, no SIGABRT"

WK=$(journal_watchdog_kills)
[ "$WK" = "0" ] || { echo "✗ COVER FAILED: journal shows $WK 'watchdog timeout' kill(s) of $ARC_UPGRADE_UNIT — the restore was aborted" >&2; exit 1; }
echo "  ✓ zero systemd watchdog-timeout kills in the unit journal"

# Anti-vacuity at hold-end (architect ruling). The upgrade ROW lives in the very DB
# the parked restore keeps DOWN — a row-state read here is UNSATISFIABLE (and the row
# can't change while the writer is parked anyway), so it was meaningless: DELETED.
# The live-cover proof is: NRestarts frozen + zero watchdog kills (above) + the DB is
# DOWN + the on-disk FLAG FILE is still present (readable with the DB down, and proof
# the upgrade has NOT concluded — a REAL parked stall, not a vacuous pass). Row
# assertions run only at the post-release terminal.
DB_HOLD=$(db_up); [ -z "$DB_HOLD" ] || { echo "✗ db is UP at hold-end — the restore stall did not genuinely park (vacuous cover test)" >&2; exit 1; }
VM_EXEC bash -c "test -e ~/statbus/tmp/upgrade-in-progress.json" || { echo "✗ the upgrade flag file is GONE at hold-end — the upgrade concluded, so there was no live stall to cover (vacuous)" >&2; exit 1; }
echo "  ✓ db down + flag file still present on disk — a live parked restore under the armed stall (not a vacuous pass)"

# ── release the stall → assert the clean rolled_back terminal + clean-slate identity ──
echo ""
echo "── releasing the stall (rm $RELEASE_FILE); expect restore completes → 'rolled_back' (≤ ${SETTLE_WATCH_S}s) ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE"
REL_TS=$(date +%s); FINAL=""
while [ $(( $(date +%s) - REL_TS )) -lt "$SETTLE_WATCH_S" ]; do
    elapsed=$(( $(date +%s) - REL_TS ))
    [ $((elapsed % 15)) -eq 0 ] && echo "[OBSERVE]   [release+${elapsed}s] NRestarts=$(arc_nrestarts) row=$(row_state)"
    ST=$(row_state)
    case "$ST" in
        rolled_back) FINAL="$ST"; echo "[OBSERVE] row reached 'rolled_back' (release+${elapsed}s)"; break ;;
        completed|failed) echo "✗ row reached '$ST' after release — a V_fail restore-cover arc must terminal at 'rolled_back'" >&2; exit 1 ;;
    esac
    sleep 5
done
[ "$FINAL" = "rolled_back" ] || {
    echo "✗ row did NOT reach 'rolled_back' within ${SETTLE_WATCH_S}s of release (last='$(row_state)')" >&2
    VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 3;' | ./sb psql" >&2 || true
    exit 1
}

echo ""
echo "── assert the clean slate (the rollback restored A byte-for-byte) ──"
assert_health_passes "$VM_NAME"
MROWS=$(migration_row_count)
[ "$MROWS" = "0" ] || { echo "✗ V_fail left a ledger row (count=$MROWS, want 0) — rollback did not unrecord it" >&2; exit 1; }
echo "  ✓ V_fail not recorded in db.migration (rolled back)"
assert_fingerprint_matches "post-rollback == post-A (after a watchdog-covered restore stall)" "$BASELINE_FP" baseline
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"

# Post-terminal NRestarts bound: at most ONE further bump over the restore-start
# value — the clean rollback's own terminal os.Exit → systemd restart. Anything
# more would mean the restore was still being killed.
NR_FINAL=$(arc_nrestarts)
if [ "$NR_FINAL" != "?" ] && [ "$NR_STALL" != "?" ]; then
    [ "$NR_FINAL" -le $(( NR_STALL + 1 )) ] || {
        echo "✗ post-terminal NRestarts=$NR_FINAL exceeds stall-baseline+1 ($((NR_STALL + 1))) — extra restarts imply the restore was SIGABRT'd, not covered" >&2
        exit 1
    }
fi
echo "  ✓ final NRestarts=$NR_FINAL ≤ stall-baseline+1 (only the clean rollback's own terminal restart)"

echo ""
echo "PASS: postswap-rollback-restore-watchdog — a real A→B(V_fail) rollback's DB restore was STALLED past WatchdogSec; the STATBUS-031 always-ping cover held (NRestarts frozen at $NR_STALL, zero watchdog kills), and on release the box reached 'rolled_back' with a byte-identical clean slate (schema+ledger+data), V unrecorded, data intact, flag removed, healthy."
