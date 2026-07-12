#!/bin/bash
# Arc: preswap-checkout-kill  (STATBUS-071 §9(5) / doc-016 — 5a, first CAT-A kill-arc)
#
# The RESHAPE of the legacy 2-preswap-checkout-kill scenario onto the arc
# framework — the proof that the kill-arc DRIVER works (the daemon-DOWN +
# `./sb install` inline-dispatch variant). The CRASH is identical to the legacy
# scenario (the REAL `killed-by-system-during-preswap-checkout` inject, service.go:4261);
# only the SCHEDULING changed: fabricate_scheduled_upgrade_row → REAL register +
# schedule (086, daemon quiesced), and the baseline v2026.05.2 → base_sha.
#
# Arc shape (A → B, killed mid-upgrade):
#   A = base_sha            install fresh, pinned; populate; trust the arc signer.
#   B = A + V               the signed arc fixture (register it; the upgrade target).
#   kill                    register B (daemon UP) → stop daemon + schedule B
#                           (persistent 'scheduled' row) → ./sb install inline-
#                           dispatch WITH STATBUS_INJECT_AT=killed-by-system-during-
#                           preswap-checkout → KillHere fires AFTER the target fetch
#                           but BEFORE the binary swap (STATBUS-060: checkout deferred).
#   RED                     flag present (PreSwap), working tree STILL at A (source),
#                           ./sb binary STILL A (unswapped) — the REAL crash state
#                           (no synthetic fabrication).
#   recovery                ./sb install → recoverFromFlag PreSwap → restoreGitState
#                           (pinned pre-upgrade branch = A) → rollback → terminal
#                           'failed'/'rolled_back'; working tree back at A; data intact.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER.
# (C_* built by construct's else-branch but unused.) VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-preswap-checkout-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-during-preswap-checkout"

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

# _dump_preswap_checkout_kill_failure_diagnostics — STATBUS-155 rider (mirrors
# postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics): on ANY
# non-zero exit, pull B's own upgrade progress log + the daemon journal + its
# row state to STDERR before cleanup_vm reaps the VM, so a red run is
# self-sufficient without needing a kept VM. Best-effort throughout (|| true)
# — a diagnostics failure must never mask the real assertion error that
# triggered this trap.
_dump_preswap_checkout_kill_failure_diagnostics() {
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

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_preswap_checkout_kill_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: preswap-checkout-kill  (kill-arc driver proof — real inject, real schedule)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS}"
echo "  SB_ARC_TRUSTED_SIGNER: ${SB_ARC_TRUSTED_SIGNER:+PRESENT (${#SB_ARC_TRUSTED_SIGNER} chars)}${SB_ARC_TRUSTED_SIGNER:-MISSING/EMPTY}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() {
    VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"
}
sb_version() {
    VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" 2>/dev/null | tr -d '\r' || echo ""
}
wt_commit() {
    VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d '\r' || echo ""
}

# ── A: install + prepare (daemon UP after this) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

# OLD_COMMIT = A's working-tree commit — restoreGitState must return us here.
OLD_COMMIT=$(wt_commit)
[ -n "$OLD_COMMIT" ] || { echo "✗ could not read working-tree HEAD after install A" >&2; exit 1; }
echo "  pre-trigger working-tree HEAD: ${OLD_COMMIT:0:8}"

# ── register B (daemon UP → verifyArtifacts flips docker_images_status='ready') ──
echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

SB_VERSION_BEFORE=$(sb_version)
echo "  pre-trigger ./sb version (A's binary): $SB_VERSION_BEFORE"

# ── schedule B daemon-down + ./sb install inline-dispatch WITH the kill inject ──
arc_schedule_daemon_down "$B_FULL"
arc_install_dispatch_with_inject "$INJECT_CLASS"

# ── RED state (the REAL crash — written by the real executeUpgrade) ──
echo ""
echo "── verifying C4 RED state (flag PreSwap, WT at source, binary unswapped) ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || {
    echo "✗ expected flag file present after the kill" >&2; exit 1; }
# (DB is down — executeUpgrade stopped it for the backup, upstream of the checkout
# kill — so row-state is checked in convergence after recovery restarts it.)
WT_DURING=$(wt_commit)
[ "$WT_DURING" = "$OLD_COMMIT" ] || { echo "✗ working tree advanced during the preswap-checkout kill ($WT_DURING vs $OLD_COMMIT) — STATBUS-060 defer-checkout violated" >&2; exit 1; }
echo "  ✓ working tree still at A (${OLD_COMMIT:0:8}) — no pre-swap checkout"
SB_DURING=$(sb_version)
[ "$SB_DURING" = "$SB_VERSION_BEFORE" ] || { echo "✗ ./sb binary changed during preswap-checkout ($SB_VERSION_BEFORE → $SB_DURING) — kill fired after binary swap?" >&2; exit 1; }
echo "  ✓ ./sb binary still A (no swap yet) — RED confirmed (flag PreSwap, source tree, unswapped)"

# ── recovery: ./sb install → recoverFromFlag PreSwap → restoreGitState → rollback ──
echo ""
echo "── recovery: ./sb install (crashed-upgrade → PreSwap rollback) ──"
REC_RC=0
VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" || REC_RC=$?
echo "  recovery ./sb install exit: $REC_RC (0 or 75=rolled-back both OK)"

# ── convergence: principled ABORT (no commit at binary-swap boundary) ──
echo ""
echo "── convergence checks ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    failed|rolled_back) echo "  ✓ principled ABORT terminal state ($FINAL_STATE)" ;;
    completed) echo "✗ state='completed' invalid for a preswap-checkout kill (never committed at binary-swap)" >&2; exit 1 ;;
    *) echo "✗ unexpected terminal state: $FINAL_STATE" >&2; exit 1 ;;
esac
assert_upgrade_row_error_matches "$VM_NAME" "INSTALL_PRECONDITION_FAILED"

WT_AFTER=$(wt_commit)
[ "$WT_AFTER" = "$OLD_COMMIT" ] || { echo "✗ working tree not restored to A ($WT_AFTER vs $OLD_COMMIT) — restoreGitState/pre-upgrade-branch path broken" >&2; exit 1; }
echo "  ✓ working tree restored to A (${OLD_COMMIT:0:8})"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
SB_AFTER=$(sb_version)
[ "$SB_AFTER" = "$SB_VERSION_BEFORE" ] || { echo "✗ ./sb binary advanced after recovery ($SB_VERSION_BEFORE → $SB_AFTER) — abort should not roll forward" >&2; exit 1; }
echo "  ✓ ./sb binary still A (abort, no roll-forward)"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: preswap-checkout-kill (kill-arc driver: real inject + real register/schedule; C4 abort to A; data intact)"
