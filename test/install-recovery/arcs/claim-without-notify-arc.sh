#!/bin/bash
# Arc: claim-without-notify  (STATBUS-098 dedicated guard)
#
# The DURABLE, DETERMINISTIC guard for the claim-without-NOTIFY property — the
# Albania gap STATBUS-098 fixes: the daemon must claim a pending 'scheduled' row
# WITHOUT a live NOTIFY (on startup-scan / the ≤30s heartbeat tick), because a
# NOTIFY fired while the daemon is down/restarting (e.g. an upgrade's DB-restart
# reconnect window) is LOST (pg NOTIFY is not durable). The (c)/(d) arcs hit this
# only PROBABILISTICALLY (the reconnect-window race); this scenario makes it
# DETERMINISTIC by scheduling while the daemon is PROVABLY stopped.
#
# Flow (single leg A→B):
#   1. install A, trust the arc signer, populate (arc_prepare_box).
#   2. register B + wait ready — with the daemon UP (so verifyArtifacts flips
#      docker_images_status='ready').
#   3. STOP the upgrade daemon → its LISTEN is gone.
#   4. schedule B → the DB trigger fires NOTIFY upgrade_apply, but NO listener →
#      the NOTIFY is GUARANTEED LOST. Assert the row sits 'scheduled' (unclaimed).
#   5. START the daemon → the STARTUP-SCAN (STATBUS-098 fix) claims B with NO live
#      NOTIFY (pg dropped it; start does not re-fire). Assert B → completed.
#   6. Assert V applied + healthy.
#
# A RED here means the daemon only claims on a live NOTIFY (the STATBUS-098 gap
# regressed) — a web-UI-scheduled upgrade would silently stall on a real box.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER.
# (C_* are built by construct's else-branch but unused here.) VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-claim-without-notify}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-1200}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
# Fast-fail budget for the CLAIM (in_progress) — distinct from the terminal budget.
# A 098-revert (daemon claims only on live NOTIFY) would never claim this lost-NOTIFY
# row → it would hang to UPGRADE_BUDGET_S (1200s = 20min). Normal claim is ~80s (the
# startup-scan / ≤30s tick); 180s is comfortable headroom yet ≪ 1200s → RED in ~3min.
CLAIM_BUDGET_S="${CLAIM_BUDGET_S:-180}"
UNIT="statbus-upgrade@statbus.service"

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

# _dump_claim_without_notify_failure_diagnostics — STATBUS-155 rider (mirrors
# postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics): on ANY
# non-zero exit, pull B's own upgrade progress log + the daemon journal + its
# row state to STDERR before cleanup_vm reaps the VM, so a red run is
# self-sufficient without needing a kept VM. Best-effort throughout (|| true)
# — a diagnostics failure must never mask the real assertion error that
# triggered this trap.
_dump_claim_without_notify_failure_diagnostics() {
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
    echo "── daemon journal ($UNIT, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u $UNIT --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit (B's row, commit_sha = ${B_FULL:-?}) ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(recovery_parked_reason,''), error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_claim_without_notify_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: claim-without-notify  (STATBUS-098 — daemon claims a 'scheduled' row with NO live NOTIFY)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  V=${V_VERSION}"
echo "  SB_ARC_TRUSTED_SIGNER: ${SB_ARC_TRUSTED_SIGNER:+PRESENT (${#SB_ARC_TRUSTED_SIGNER} chars)}${SB_ARC_TRUSTED_SIGNER:-MISSING/EMPTY}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"
}

# ── A: install + prepare (daemon is UP after this) ──
arc_prepare_box

# ── register B with the daemon UP so docker_images_status flips to 'ready' ──
echo ""
echo "── register B (daemon up → verifyArtifacts flips images-ready) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

# ── STOP the daemon → the schedule's NOTIFY will have no listener (lost) ──
echo ""
echo "── stopping the upgrade daemon (its NOTIFY listener goes away) ──"
VM_EXEC systemctl --user stop "$UNIT" 2>/dev/null || true
DOWN_STATE=$(VM_EXEC systemctl --user is-active "$UNIT" 2>/dev/null | tr -d ' \r\n' || echo "inactive")
[ "$DOWN_STATE" != "active" ] || { echo "✗ daemon still active after stop (state=$DOWN_STATE) — cannot guarantee a lost NOTIFY" >&2; exit 1; }
echo "  ✓ daemon is '$DOWN_STATE' (not active)"

# ── schedule B → NOTIFY fires into the void (no listener) → row stays 'scheduled' ──
echo ""
echo "── schedule B while the daemon is DOWN (NOTIFY guaranteed lost) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"
sleep 5
ST=$(upgrade_state)
[ "$ST" = "scheduled" ] || { echo "✗ expected B 'scheduled' while daemon down, got '$ST' (someone claimed it — daemon not really down?)" >&2; exit 1; }
echo "  ✓ B is 'scheduled' + daemon down → its NOTIFY was lost (no live consumer)"
dump_daemon_state "daemon stopped, B scheduled"

# ── START the daemon → STARTUP-SCAN (STATBUS-098) claims B with NO live NOTIFY ──
echo ""
echo "── starting the daemon → the startup-scan or ≤30s tick must claim B (no NOTIFY exists) ──"
VM_EXEC bash -c "systemctl --user reset-failed $UNIT 2>/dev/null; systemctl --user start $UNIT"

START_TS=$(date +%s)
FINAL=""; SAW_CLAIM=0
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    ST=$(upgrade_state)
    case "$ST" in
        in_progress) SAW_CLAIM=1 ;;
        completed|failed|rolled_back) SAW_CLAIM=1; FINAL="$ST"; echo "  B reached state='$ST' (t+${elapsed}s after daemon start)"; break ;;
    esac
    # FAST-FAIL: B must be CLAIMED (in_progress/terminal) within CLAIM_BUDGET_S via
    # the startup-scan or the ≤30s tick — there is NO live NOTIFY. A daemon that only
    # acts on a live NOTIFY (STATBUS-098 regressed) would never claim → RED here in
    # ~3min instead of hanging to the 1200s terminal budget.
    if [ "$SAW_CLAIM" = "0" ] && [ "$elapsed" -ge "$CLAIM_BUDGET_S" ]; then
        echo "✗ B NOT CLAIMED within ${CLAIM_BUDGET_S}s of daemon start (state='$ST') — STATBUS-098 no-NOTIFY claim (startup-scan or ≤30s tick) regressed" >&2
        VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
        exit 1
    fi
    if [ "$elapsed" -ge "$UPGRADE_BUDGET_S" ]; then
        echo "✗ B claimed but not terminal within ${UPGRADE_BUDGET_S}s of daemon start (state='$ST')" >&2
        VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
        exit 1
    fi
    sleep 5
done
[ "$FINAL" = "completed" ] || { echo "✗ B did NOT complete (got '$FINAL') after claim-without-NOTIFY" >&2; exit 1; }

# ── assert the upgrade really happened (claimed via scan, applied for real) ──
echo "── assert V applied + healthy ──"
RC=$(fixture_row_count)
[ "$RC" = "1" ] || { echo "✗ V not applied: public.upgrade_arc_fixture count=$RC (want 1)" >&2; exit 1; }
assert_demo_data_present "$VM_NAME"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: claim-without-notify (daemon claimed a 'scheduled' row via the startup-scan or ≤30s tick with NO live NOTIFY; V applied; healthy)"
