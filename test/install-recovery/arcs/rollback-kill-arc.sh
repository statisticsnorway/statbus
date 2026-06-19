#!/bin/bash
# Arc: rollback-kill  (STATBUS-071 §9(5) / doc-016 — 5b, CAT-A; C9) — INSTRUMENTED
#
# *** OBSERVATIONAL / DIAGNOSTIC RUN (asserts deliberately minimal) ***
# The architect found the legacy 4-rollback-kill "both-outcomes" model is STALE:
# recoverFromFlag (service.go:766) branches by FLAG PHASE —
#   • PreSwap  → :945 recoveryRollback  (UNCONDITIONAL; "never self-heal" — C5's contract)
#   • PostSwap/Resuming → :829 forward-recovery
# A binary-swap (C5) kill = a PreSwap flag, so the 2nd-dispatch recovery takes the
# PreSwap → recoveryRollback branch (NOT forward-recovery) — the legacy "outcome A
# (forward→completed)" is Resuming-branch behaviour MISAPPLIED to a PreSwap wedge
# and cannot happen post the never-self-heal guard. WORSE: the PreSwap light-
# rollback (:954) may not even invoke builtin-rollback (:5620) where the C9 inject
# lives → C9 may fire on NEITHER path.
#
# Truth is empirical. This run OBSERVES (logs, [OBSERVE] markers) the REAL recovery
# path so we can rewrite the asserts DETERMINISTIC afterwards: the wedge flag phase,
# the 2nd-dispatch exit (137 ⟹ :5620 reached + C9 fired; 0/75 ⟹ :5620 NOT reached),
# the recoverFromFlag branch (read the ./sb install output above each [OBSERVE]), the
# terminal row state. It PASSES on any coherent terminal so the run completes and we
# read the logs; the ONLY hard precondition is that the C5 wedge establishes (else
# there is nothing to observe).
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-rollback-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"

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

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: rollback-kill  (C9 — INSTRUMENTED observational run)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
flag_dump()     { VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null" 2>/dev/null || echo "(no flag file)"; }
flag_present()  { VM_EXEC bash -c "test -f ~/statbus/tmp/upgrade-in-progress.json && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }

# ── A: install + prepare; register; schedule daemon-down ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"

# ── 1st dispatch: C5 binary-swap kill → establish the wedge (HARD precondition) ──
echo ""
echo "── 1st dispatch: C5 binary-swap kill (set up the PreSwap wedge) ──"
arc_install_dispatch_with_inject "killed-by-system-during-binary-swap"
WEDGE_RC="$ARC_DISPATCH_RC"
[ "$WEDGE_RC" = "137" ] || { echo "✗ 1st dispatch exited $WEDGE_RC (expected 137) — the C5 kill did not fire; no wedge to observe" >&2; exit 1; }
echo "[OBSERVE] wedge: C5 binary-swap kill exit=$WEDGE_RC"
echo "[OBSERVE] wedge flag JSON (expect Phase=PreSwap):"
flag_dump | sed 's/^/[OBSERVE]   /'

# ── 2nd dispatch: C9 builtin-rollback inject during recovery — OBSERVE the path ──
echo ""
echo "── 2nd dispatch (recovery + C9 builtin-rollback inject) — OBSERVATIONAL ──"
echo "    (read the ./sb install output below for the recoverFromFlag branch it takes)"
arc_install_dispatch_with_inject "killed-by-system-during-builtin-rollback"
SECOND_RC="$ARC_DISPATCH_RC"
echo "[OBSERVE] 2nd-dispatch (C9 recovery) exit=$SECOND_RC"
if [ "$SECOND_RC" = "137" ]; then
    echo "[OBSERVE] ⟹ C9 (:5620 builtin-rollback) FIRED — recovery REACHED builtin-rollback (legacy outcome-B path)"
else
    echo "[OBSERVE] ⟹ C9 (:5620) NOT reached this run (exit=$SECOND_RC) — the PreSwap recoveryRollback (:945/:954) did NOT invoke :5620 (architect hypothesis); real C9 coverage needs a forward-fails-rollback wedge (self-failing-V, Q5-2)"
fi
echo "[OBSERVE] flag present after 2nd dispatch: $(flag_present)"
echo "[OBSERVE] flag JSON after 2nd dispatch:"
flag_dump | sed 's/^/[OBSERVE]   /'
echo "[OBSERVE] row state after 2nd dispatch: $(upgrade_state)"

# ── cleanup: drive to a terminal so the box is coherent + we read the final state ──
if [ "$(flag_present)" = "yes" ]; then
    echo ""
    echo "── cleanup dispatch: ./sb install (no inject) → drive to terminal ──"
    CLEAN_RC=0
    VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" || CLEAN_RC=$?
    echo "[OBSERVE] cleanup ./sb install exit=$CLEAN_RC (0 or 75=rolled-back both OK)"
fi

FINAL_STATE=$(upgrade_state)
echo ""
echo "── FINAL OBSERVATIONS ──"
echo "[OBSERVE] FINAL row state: $FINAL_STATE"
echo "[OBSERVE] FINAL flag present: $(flag_present)"
echo "[OBSERVE] C9 fired this run: $([ "$SECOND_RC" = "137" ] && echo YES || echo NO)"

# OBSERVATIONAL sanity only (NO false-RED on the recovery path — that's what we're
# here to discover): the box should reach SOME coherent terminal + stay healthy.
case "$FINAL_STATE" in
    completed|rolled_back|failed) echo "  ✓ box reached a coherent terminal ($FINAL_STATE)" ;;
    *) echo "  ⚠ box NOT at a coherent terminal ($FINAL_STATE) — note for the deterministic rewrite" ;;
esac
assert_demo_data_present "$VM_NAME" || echo "  ⚠ demo data not present — note for the rewrite"
assert_health_passes "$VM_NAME" || echo "  ⚠ health did not pass — note for the rewrite"

echo ""
echo "OBSERVATIONAL PASS: rollback-kill instrumented — grep [OBSERVE] for the REAL recovery path (flag phase, recoverFromFlag branch, whether C9/:5620 fired, terminal state). Asserts to be rewritten DETERMINISTIC from this evidence."
