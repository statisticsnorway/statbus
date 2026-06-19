#!/bin/bash
# Arc: postswap-migration-timeout  (STATBUS-071 §9(5) / doc-016 — 5c CAT-B; C12)
#
# Reshape of the legacy 3-postswap-migration-timeout (C12) onto the PROVEN stall-
# dispatch driver (5c/postswap-watchdog-reconnect, GREEN run 27817729943). Same
# mechanism — only the inject CLASS + stall site differ. Only the SCHEDULING swapped
# (fabricate → real register+schedule) + baseline (v2026.05.2 → base_sha).
#
# What it proves (STATBUS-012): a migration that runs longer than WatchdogSec=120s
# would, without a heartbeat, trip systemd's watchdog → SIGABRT → restart loop (the
# rune-wedge shape). The WATCHDOG=1 ticker around the boot-migrate subprocess keeps
# the unit alive across the >120s stalled migration → it COMPLETES; NRestarts stays
# bounded (delta ≤ 1).
#
# Must-adds (proven in C15): (c) arc_install_stall_dropin RESTARTS the unit so the
# daemon process carries STATBUS_INJECT_AT; (e) after the hold, assert the row is
# STILL in_progress (the stall genuinely held ≥ WatchdogSec) before NRestarts/release;
# (a) NRestarts baseline AFTER in_progress (post the dispatch reset-failed).
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-migration-timeout}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
STALL_HOLD_S="${STALL_HOLD_S:-180}"            # > WatchdogSec=120s — load-bearing
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"
INPROGRESS_BUDGET_S="${INPROGRESS_BUDGET_S:-300}"
INJECT_CLASS="migration-slower-than-systemd-unit-timeout"
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
    VM_EXEC bash -c "rm -f $RELEASE_FILE 2>/dev/null; rm -f ~/.config/systemd/user/${ARC_UPGRADE_UNIT}.d/inject.conf 2>/dev/null; systemctl --user daemon-reload 2>/dev/null" 2>/dev/null || true
}
trap 'rc=$?; _arc_cleanup; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-migration-timeout  (C12 — stall-dispatch; WATCHDOG=1 ticker covers boot-migrate)"
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

# ── (c) arm the migrate stall via dropin + RESTART the unit (BEFORE scheduling) ──
arc_install_stall_dropin "$INJECT_CLASS" "$RELEASE_FILE"

echo ""
echo "── schedule B (daemon listening post-restart → claims via NOTIFY/scan) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

echo ""
echo "── waiting for B → in_progress (unit claims + reaches the migrate stall) ──"
arc_wait_row_state "$B_FULL" "in_progress" "$INPROGRESS_BUDGET_S"

NRESTARTS_BASELINE=$(arc_nrestarts)   # (a) post the dispatch reset-failed (service.go:3926)
echo "  baseline NRestarts (post-dispatch-reset): $NRESTARTS_BASELINE"

echo ""
echo "── holding the migrate stall ${STALL_HOLD_S}s (> WatchdogSec=120s) — the WATCHDOG=1 ticker must keep the unit alive ──"
sleep "$STALL_HOLD_S"

# (e) ANTI-FALSE-PASS: the stall MUST still be holding (row in_progress).
ST_AFTER_HOLD=$(row_state)
[ "$ST_AFTER_HOLD" = "in_progress" ] || { echo "✗ ANTI-FALSE-PASS: row is '$ST_AFTER_HOLD' after the ${STALL_HOLD_S}s hold (expected in_progress) — the migrate stall did NOT hold past WatchdogSec (dropin/restart/ordering failed); NRestarts-bounded would be vacuous" >&2; exit 1; }
echo "  ✓ row STILL in_progress after ${STALL_HOLD_S}s — the migrate stall genuinely held past WatchdogSec"

NRESTARTS_DURING=$(arc_nrestarts)
echo "  NRestarts at stall-hold-end: $NRESTARTS_DURING (baseline=$NRESTARTS_BASELINE)"

echo ""
echo "── releasing the stall (rm $RELEASE_FILE) → migration proceeds ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE"
arc_wait_row_state "$B_FULL" "completed" "$((UPGRADE_BUDGET_S - STALL_HOLD_S))"

echo ""
echo "── STATBUS-012 regression check (LOAD-BEARING) ──"
NRESTARTS_FINAL=$(arc_nrestarts)
RESTART_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$RESTART_DELTA"
if [ "$RESTART_DELTA" -gt 1 ]; then
    echo "✗ NRestarts grew by $RESTART_DELTA across the migrate stall — the WATCHDOG=1 ticker is NOT covering boot-migrate; systemd SIGABRTed the unit at WatchdogSec (STATBUS-012 cover regressed)" >&2
    exit 1
fi
echo "  ✓ NRestarts within tolerance (delta ≤ 1) — the boot-migrate watchdog ticker held the unit alive across the stall"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "$ARC_UPGRADE_UNIT" 2
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: postswap-migration-timeout (boot-migrate survived a ${STALL_HOLD_S}s stalled migration under WatchdogSec=120s; NRestarts delta=$RESTART_DELTA; completed; data intact)"
