#!/bin/bash
# Arc: postswap-converged-selfheal  (STATBUS-071 P5 — the LIVE producer for resumeNewSb's
# containers-at-target SELF-HEAL to 'completed'; the real coverage that replaces the retired
# rune-wedge fabrication).
#
# WHAT THIS PROVES: a real upgrade that CONVERGES (migrate applied, services started, health
# passed, maintenance off) but crashes in the ~ms window BEFORE the ledger's 'completed' write
# lands leaves a service-held flag + an in_progress row on a genuinely-serving box. The next
# boot's resumeNewSb — containersAtFlagTarget TRUE, no pending migrations, healthCheck passes —
# SELF-HEALS the row to 'completed' without re-running the pipeline. This is the live rune class
# (the Apr-24 SDNOTIFY collision) minus its now-extinct route; every line of machinery that runs
# is REAL. The former 3-postswap-rune-wedge scenario FABRICATED this state; here the producer is
# a real inject at the exact converged-but-unlanded instant.
#
# CONSTRUCTION (real path, no fabrication): install A → real register+schedule of the WORKING
# lineage B (V applies cleanly) → a real ./sb install dispatch runs executeUpgrade inline:
# migrate V succeeds → StartServices → healthCheck PASSES → setMaintenance(false) → the marker
# killed-after-health-before-completed-write (KindKill, service.go, os.Exit(137)) fires BEFORE
# the completed terminalUpdate. The box is converged + serving; the row is in_progress and the
# service-held flag (Phase=NewSbSwapped) is on disk — NOT truncated (unlike the flagless-selfheal
# arc): this flag is FAITHFUL, so the next boot's recoverFromFlag routes it to resumeNewSb, whose
# self-heal completes it. Then the daemon recovery boot drives the real self-heal.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex, working lineage), B_BRANCH, V_VERSION,
#   SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-converged-selfheal}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
CONVERGE_BUDGET_S="${CONVERGE_BUDGET_S:-600}"

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

UPGRADE_UNIT="statbus-upgrade@statbus.service"
FLAG_PATH="tmp/upgrade-in-progress.json"

_dump_selfheal_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (row + journal + flag) ══════════" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(error,'') FROM public.upgrade ORDER BY id DESC LIMIT 5;\" | ./sb psql -x" >&2 || true
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || true
    VM_EXEC bash -c "cat ~/statbus/$FLAG_PATH 2>/dev/null || echo '(flag absent)'" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_selfheal_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-converged-selfheal  (real converged crash before the completed write → resumeNewSb self-heal → completed)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  V=${V_VERSION}"
echo "════════════════════════════════════════════════════════════════"

row_state()   { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
row_error()   { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(error,'') FROM public.upgrade ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d '\r' || echo "?"; }
flag_present(){ VM_EXEC bash -c "test -f ~/statbus/$FLAG_PATH && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
arm_since()   { VM_EXEC bash -c "date '+%Y-%m-%d %H:%M:%S'" 2>/dev/null | tr -d '\r'; }
journal_has() { VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --since \"$2\" --no-pager 2>/dev/null | grep -qF \"$1\" && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }

# ── A: install + prepare; snapshot ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ── real dispatch on the working lineage, killed at the CONVERGED-but-unlanded instant ──
echo ""
echo "── register B (working lineage, daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
arc_schedule_daemon_down "$B_FULL"

echo ""
echo "── dispatch B with the converged kill (migrate applies → health passes → maintenance off → kill BEFORE the completed write) ──"
arc_install_dispatch_with_inject "killed-after-health-before-completed-write"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ dispatch exit was $ARC_DISPATCH_RC, expected 137 — the converged kill (after health + setMaintenance(false), before the completed write) did not fire" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ no flag file after the converged kill — the crash must leave a faithful service-held flag" >&2; exit 1; }
# The box is CONVERGED (health passed before the kill), so the DB is UP — no rollback/restore
# window here (unlike the mid-rollback churn arc). The row must be in_progress: the kill preceded
# the completed terminalUpdate.
[ "$(row_state)" = "in_progress" ] || { echo "✗ row is not 'in_progress' after the converged kill (got '$(row_state)') — the completed write must not have landed" >&2; exit 1; }
echo "  ✓ real converged crash: exit 137, faithful flag present, row in_progress, box serving at B"

# ── daemon recovery boot: recoverFromFlag → resumeNewSb → containers-at-target self-heal → completed ──
echo ""
echo "── starting the daemon (recovery boot): resumeNewSb self-heals the converged row to completed ──"
SINCE=$(arm_since)
vm_start_unit "$UPGRADE_UNIT"

echo ""
echo "── assert convergence: row → completed, error NULL, [completed-self-heal] label, flag absent ──"
CONV_START=$(date +%s)
while true; do
    ST=$(row_state)
    [ "$ST" = "completed" ] && { echo "  ✓ row self-healed to 'completed' (t+$(( $(date +%s) - CONV_START ))s)"; break; }
    case "$ST" in failed|rolled_back) echo "✗ row reached terminal '$ST' instead of the self-heal 'completed'" >&2; exit 1 ;; esac
    [ $(( $(date +%s) - CONV_START )) -lt "$CONVERGE_BUDGET_S" ] || { echo "✗ row did not self-heal to 'completed' within ${CONVERGE_BUDGET_S}s (last '$ST')" >&2; exit 1; }
    sleep 5
done
CONV_ERR=$(row_error)
[ -z "$CONV_ERR" ] || { echo "✗ error is not NULL after the self-heal: '$CONV_ERR'" >&2; exit 1; }
# The PRODUCT's exact self-heal label (service.go LabelCompletedSelfHeal = 'completed-self-heal',
# logged at the self-heal terminalUpdate) — proves resumeNewSb's self-heal branch (NOT the
# flagless completeInProgressUpgrade belt, NOT the normal applyNewSbUpgrading completion) converged
# THIS row.
[ "$(journal_has "upgrade row [completed-self-heal]" "$SINCE")" = "yes" ] || { echo "✗ journal lacks resumeNewSb's own [completed-self-heal] label — the row did not converge via the containers-at-target self-heal" >&2; exit 1; }
[ "$(flag_present)" = "no" ] || { echo "✗ flag still present after the self-heal — resumeNewSb must remove it on completion" >&2; exit 1; }
echo "  ✓ completed + error NULL, [completed-self-heal] logged, flag absent"

echo ""
echo "── assert the resume-death latch stayed SILENT (ONE death, before resume — never a death DURING resume) ──"
[ "$(journal_has "UPGRADE_DIED_DURING_RESUME" "$SINCE")" = "no" ] || { echo "✗ UPGRADE_DIED_DURING_RESUME fired — the latch must stay silent: the single death PRECEDED the resume, it did not happen DURING it" >&2; exit 1; }
echo "  ✓ no UPGRADE_DIED_DURING_RESUME — the resume-death latch stayed silent (self-heal, not a re-resume)"

echo ""
echo "── assert NRestarts bounded (the converged kill's own exit is the only restart; no churn) ──"
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 2

echo ""
echo "── assert app/db/rest/worker serving + data intact (a self-healed box is a serving box) ──"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# ── assert the READ-ONLY WINDOW was lifted BY THE SELF-HEAL TAIL (STATBUS-071 P5) ──
# The converged kill fired at the CONVERGED-but-unlanded instant, so the read-only
# window (engaged at step 2) is still ON at the crash; resumeNewSb's self-heal — the
# THIRD completed writer — must lift it itself. Two-part discriminator (a write probe
# alone can't tell the arms apart — pre-fix, the boot backstop clearStaleReadOnlyWindow
# runs on the NEXT boot and clears the window, so a probe would eventually be green on
# BOTH arms):
#   (a) NEGATIVE journal assert — the backstop 'STATBUS-163 BACKSTOP' must be ABSENT in
#       the arm window. Its firing is defined as an investigation trigger; its silence
#       proves the self-heal tail lifted the window ITSELF (the right mechanism).
#   (b) write-probe BELT — a fresh psql session must accept a write (no read_only 25006),
#       proving the operator-visible truth (box accepts writes) regardless of mechanism.
#       BEGIN/UPDATE(0-row still trips read-only)/ROLLBACK keeps the box byte-identical;
#       NOT a temp table (temp writes are ALLOWED under read-only → illusory).
echo ""
echo "── assert STATBUS-071 P5: the self-heal tail lifted the read-only window itself (backstop silent) + box accepts writes ──"
[ "$(journal_has "STATBUS-163 BACKSTOP" "$SINCE")" = "no" ] || { echo "✗ boot backstop 'STATBUS-163 BACKSTOP' fired in the arm window — the self-heal tail did NOT lift the read-only window itself (P5 regressed)" >&2; exit 1; }
echo "  ✓ no STATBUS-163 BACKSTOP in the arm window — the self-heal tail lifted the window itself"
WRITE_PROBE=$(VM_EXEC bash -c "cd ~/statbus && printf 'BEGIN;\nUPDATE public.system_info SET value = value;\nROLLBACK;\n' | ./sb psql 2>&1" || true)
if echo "$WRITE_PROBE" | grep -qiE "read_only_sql_transaction|read-only transaction|25006"; then
    echo "✗ write probe hit read-only (25006) — the window is still ON after the self-heal (P5 did not lift it):" >&2
    echo "$WRITE_PROBE" >&2
    exit 1
fi
echo "  ✓ write probe accepted (BEGIN/UPDATE/ROLLBACK, no 25006) — the box serves writes"

echo ""
echo "PASS: postswap-converged-selfheal — a REAL working-lineage upgrade converged (migrate applied, services started, health passed, maintenance off) then crashed at the REAL converged-but-unlanded instant (killed-after-health-before-completed-write, exit 137; faithful flag present, row in_progress, box serving); the next boot's resumeNewSb containers-at-target self-heal converged the row to 'completed' (error NULL, [completed-self-heal] logged, flag removed), the resume-death latch stayed silent (UPGRADE_DIED_DURING_RESUME absent — one death, before resume), NRestarts bounded, app/db/rest/worker serving, data intact, and the read-only window was lifted BY THE SELF-HEAL TAIL (no STATBUS-163 BACKSTOP in the arm window; a fresh write is accepted with no 25006 — the third completed writer is now serve-proven in the full STATBUS-192 sense). The live producer that replaces the retired rune-wedge fabrication — on GREEN the rune-wedge scenario retires and fabricate_resume_state's caller count drops."
