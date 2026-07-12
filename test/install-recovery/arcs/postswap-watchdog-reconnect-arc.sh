#!/bin/bash
# Arc: postswap-watchdog-reconnect  (STATBUS-071 §9(5) / doc-016 — 5c, CAT-B; C15)
#
# Reshape of the legacy 3-postswap-watchdog-reconnect (C15, Race D) onto the NEW
# stall-dispatch driver (the 3rd variant: daemon-RUN, the systemd UNIT runs the
# upgrade under WatchdogSec=120s; a STALL is injected via a systemd dropin). Only
# the SCHEDULING swapped (fabricate → real register+schedule, 086) + baseline
# (v2026.05.2 → base_sha). The stall class, WATCHDOG=1 ticker, NRestarts-bounded
# contract are the legacy's (verbatim).
#
# What it proves: applyPostSwap's docker-compose-up + waitForDBHealth + reconnect
# parks the main goroutine; the WATCHDOG=1-around-reconnect ticker keeps pinging
# from a dedicated goroutine so systemd's WatchdogSec=120s does NOT SIGABRT the unit
# across a >120s stall. LOAD-BEARING: NRestarts delta ≤ 1 through the stall + the
# upgrade COMPLETES (the unit survives, never reaped).
#
# Architect must-adds baked in:
#   (c) RESTART-FOR-ENV: arc_install_stall_dropin restarts the unit so the daemon
#       PROCESS carries STATBUS_INJECT_AT (a daemon-reload alone won't — env is read
#       at start; executeUpgrade runs in the daemon). Done BEFORE scheduling B.
#   (e) ANTI-FALSE-PASS: after the hold, assert the row is STILL in_progress (the
#       stall held ≥ WatchdogSec) BEFORE measuring NRestarts/releasing — else a
#       fast-complete (stall never engaged) → 0 restarts → vacuous "PASS".
#   (a) NRestarts baseline is captured AFTER in_progress (executeUpgrade reset-failed
#       at dispatch, service.go:3926) → delta measured THROUGH the stall, not across.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-watchdog-reconnect}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
STALL_HOLD_S="${STALL_HOLD_S:-180}"            # > WatchdogSec=120s — load-bearing
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"
INPROGRESS_BUDGET_S="${INPROGRESS_BUDGET_S:-300}"
INJECT_CLASS="service-watchdog-timeout-during-db-reconnect-after-container-restart"
RELEASE_FILE="/tmp/arc-stall-release"

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
    # Best-effort: remove the dropin + release file so a KEEP_VM box is left clean.
    VM_EXEC bash -c "rm -f $RELEASE_FILE 2>/dev/null; rm -f ~/.config/systemd/user/${ARC_UPGRADE_UNIT}.d/inject.conf 2>/dev/null; systemctl --user daemon-reload 2>/dev/null" 2>/dev/null || true
}

# _dump_watchdog_reconnect_failure_diagnostics — STATBUS-155 rider (mirrors
# postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics): on ANY
# non-zero exit, pull B's own upgrade progress log + the daemon journal + its
# row state to STDERR BEFORE _arc_cleanup removes the release marker / inject
# drop-in and cleanup_vm reaps the VM, so a red run is self-sufficient without
# needing a kept VM. Best-effort throughout (|| true) — a diagnostics failure
# must never mask the real assertion error that triggered this trap.
_dump_watchdog_reconnect_failure_diagnostics() {
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

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_watchdog_reconnect_failure_diagnostics; fi; _arc_cleanup; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-watchdog-reconnect  (C15 — stall-dispatch; WATCHDOG=1 ticker keeps the unit alive)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  stall-hold=${STALL_HOLD_S}s (> WatchdogSec=120s)"
echo "════════════════════════════════════════════════════════════════"

row_state() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare; register B (daemon up) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

# ── (c) arm the stall via dropin + RESTART the unit (BEFORE scheduling) ──
arc_install_stall_dropin "$INJECT_CLASS" "$RELEASE_FILE"

# ── schedule B → the schedule's NOTIFY reaches the now-listening daemon (098
#    startup-scan/tick are the fallback if the NOTIFY races) → it claims + dispatches ──
echo ""
echo "── schedule B (daemon listening post-restart → claims via NOTIFY/scan) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

# ── wait for the unit to claim B + drive into applyPostSwap → the reconnect stall ──
echo ""
echo "── waiting for B → in_progress (unit claims + reaches the reconnect stall) ──"
arc_wait_row_state "$B_FULL" "in_progress" "$INPROGRESS_BUDGET_S"

# (a) baseline NRestarts AFTER in_progress (post the dispatch reset-failed, service.go:3926).
NRESTARTS_BASELINE=$(arc_nrestarts)
echo "  baseline NRestarts (post-dispatch-reset): $NRESTARTS_BASELINE"

# ── hold the stall > WatchdogSec ──
echo ""
echo "── holding the stall ${STALL_HOLD_S}s (> WatchdogSec=120s) — the WATCHDOG=1 ticker must keep the unit alive ──"
sleep "$STALL_HOLD_S"

# (e) ANTI-FALSE-PASS: the stall MUST still be holding (row in_progress) — else a
# fast-complete means the stall never engaged and NRestarts-bounded is vacuous.
ST_AFTER_HOLD=$(row_state)
[ "$ST_AFTER_HOLD" = "in_progress" ] || { echo "✗ ANTI-FALSE-PASS: row is '$ST_AFTER_HOLD' after the ${STALL_HOLD_S}s hold (expected in_progress) — the stall did NOT hold past WatchdogSec (dropin/restart/ordering failed); NRestarts-bounded would be a vacuous pass" >&2; exit 1; }
echo "  ✓ row STILL in_progress after ${STALL_HOLD_S}s — the stall genuinely held past WatchdogSec"

NRESTARTS_DURING=$(arc_nrestarts)
echo "  NRestarts at stall-hold-end: $NRESTARTS_DURING (baseline=$NRESTARTS_BASELINE)"

# ── release the stall → reconnect proceeds → upgrade completes ──
echo ""
echo "── releasing the stall (rm $RELEASE_FILE) → reconnect proceeds ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE"
arc_wait_row_state "$B_FULL" "completed" "$((UPGRADE_BUDGET_S - STALL_HOLD_S))"

# ── assertions ──
echo ""
echo "── Race D regression check (LOAD-BEARING) ──"
NRESTARTS_FINAL=$(arc_nrestarts)
RESTART_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$RESTART_DELTA"
if [ "$RESTART_DELTA" -gt 1 ]; then
    echo "✗ NRestarts grew by $RESTART_DELTA across the stall — the WATCHDOG=1-around-reconnect ticker is NOT firing; systemd SIGABRTed the unit at the WatchdogSec mark (Race D fix regressed)" >&2
    exit 1
fi
echo "  ✓ NRestarts within tolerance (delta ≤ 1) — the reconnect-watchdog ticker held the unit alive across the stall"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "$ARC_UPGRADE_UNIT" 2
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: postswap-watchdog-reconnect (WATCHDOG=1 ticker kept the unit alive across a ${STALL_HOLD_S}s reconnect stall; NRestarts delta=$RESTART_DELTA; upgrade completed; data intact)"
