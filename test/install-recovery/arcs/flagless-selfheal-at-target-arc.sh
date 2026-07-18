#!/bin/bash
# Arc: flagless-selfheal-at-target  (STATBUS-071 comment #17 — the REAL-PATH
# successor to the fabricated scenario 4-flagless-selfheal-at-target; architect-
# ruled; producer = the dual-use at-target kill site).
#
# WHAT THIS PROVES (STATBUS-039 flagless self-heal, on a REAL orphan): an
# [at-target in_progress row + NO flag] state — which the fabricated scenario
# SYNTHESISED — arises here entirely via real machinery, and completeInProgressUpgrade
# converges it to 'completed'. The orphan's genesis:
#   1. A REAL dispatched upgrade to B is killed AT-TARGET
#      (killed-by-system-after-migrations-before-completion): migrations applied +
#      binary at B, but the resume died before state=completed → a real
#      Phase=NewSbUpgrading flag + an in_progress row, box genuinely at-target.
#   2. TRUNCATE the flag file on the VM (environment manipulation of real machinery
#      state — the blessed genre; a real crash-during-flag-write / tmpfs-loss shape).
#   3. The next boot's REAL corrupt-flag reader (recoverFromFlag: json.Unmarshal
#      fails → "FLAG_CORRUPT: … removing" → os.Remove, row UNTOUCHED, service.go:1008)
#      removes it → now [in_progress row + NO flag], produced for real.
#   4. The SAME boot's completeInProgressUpgrade (service.go:2860) finds the orphan,
#      passes DB-health + observed-state (AtTarget: binary==commit_sha, db.migration
#      max ≥ on-disk max), and marks state='completed', error=NULL, logging its own
#      LabelCompletedFromInProgress ("[completed-from-in-progress]").
# On this arc's GREEN the fabricated scenario 4-flagless-selfheal-at-target DELETES
# (its interim-net deletion condition) and fabricate_resume_state drops one caller
# toward AC#4's zero-callers end state.
#
# The end state is a SERVING box (STATBUS-192): completeInProgressUpgrade's completed
# write is now serve-proven — after the DB-health + at-target gates it runs the SAME tail
# applyNewSbUpgrading runs (Step 11 StartServices → app health gate → maintenance off)
# BEFORE state=completed, and a start/health failure parks at-target instead of certifying
# a dark box. The kill site here (killed-by-system-after-migrations-before-completion,
# service.go:6055) fires BEFORE Step 11, so the orphan's app/worker/rest are genuinely
# DOWN — which makes this arc's assert_health_passes the STATBUS-192 RED→GREEN oracle: RED
# on pre-fix code (the row goes 'completed' while the app never started — a dark box), GREEN
# with the fix (the self-heal starts services + health-gates before completing). The
# now-deleted fabricated scenario's own health-assert was ILLUSORY — it passed only because
# its construction never touched the app (the box was already running from the initial
# install), not because the self-heal itself produced a serving instance.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION (working lineage —
# no construct spec; reuses the shared working B). VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-flagless-selfheal-at-target}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
CONVERGE_BUDGET_S="${CONVERGE_BUDGET_S:-600}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required - the working lineage B migration set}"
: "${V_VERSION_2:?V_VERSION_2 required - the working lineage B applies V1+V2, so at-target max == V_VERSION_2}"

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
    echo "══════════ failure diagnostics (rows + journal + flag) ══════════" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, commit_sha, COALESCE(error,'') FROM public.upgrade ORDER BY id DESC LIMIT 5;\" | ./sb psql -x" >&2 || true
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 300 2>/dev/null" >&2 || true
    VM_EXEC bash -c "ls -la ~/statbus/$FLAG_PATH 2>&1; echo '--- flag bytes ---'; wc -c ~/statbus/$FLAG_PATH 2>/dev/null" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_selfheal_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: flagless-selfheal-at-target  (real at-target kill → truncate flag → corrupt-reader removes → self-heal to completed)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

# ── helpers ──────────────────────────────────────────────────────────────────
row_state_for() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$1' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
row_error_for() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(error,'') FROM public.upgrade WHERE commit_sha = '$1' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d '\r' || echo "?"; }
psql_scalar() { VM_EXEC bash -c "cd ~/statbus && echo \"$1\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
box_head() { VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
flag_present() { VM_EXEC bash -c "test -f ~/statbus/$FLAG_PATH && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
# ARM-scoped journal check (the paid-for lesson — the unit journal persists across
# restarts; anchor at the VM clock captured before the recovery boot).
arm_since() { VM_EXEC bash -c "date '+%Y-%m-%d %H:%M:%S'" 2>/dev/null | tr -d '\r'; }
journal_has() { VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --since \"$2\" --no-pager 2>/dev/null | grep -qF \"$1\" && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }

# ── A: install + prepare + snapshot ──────────────────────────────────────────
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ── crash B AT-TARGET (kill after migrations, before completion) ──
echo ""
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -5" || true
# Candidate must verify READY while the daemon is UP (its discovery flips
# images-status); arc_schedule_daemon_down stops it — a down-daemon dispatch would
# refuse "images not yet verified ready" and the kill would never fire.
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
arc_schedule_daemon_down "$B_FULL"
arc_install_dispatch_with_inject "killed-by-system-after-migrations-before-completion"
[ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ dispatch exit was $ARC_DISPATCH_RC, expected 137 (KillHere SIGKILL) — the at-target kill did not fire" >&2; exit 1; }

echo ""
echo "── assert crashed AT-TARGET: in_progress row, flag present, box genuinely at-target (V applied, HEAD==B) ──"
[ "$(row_state_for "$B_FULL")" = "in_progress" ] || { echo "✗ B is not 'in_progress' after the at-target kill (got '$(row_state_for "$B_FULL")')" >&2; exit 1; }
[ "$(flag_present)" = "yes" ] || { echo "✗ no flag file after the kill — the at-target kill did not leave a resumable flag" >&2; exit 1; }
DBMAX=$(psql_scalar "SELECT max(version) FROM db.migration;")
# The working lineage's B writes TWO migrations (V1 at V_VERSION + V2 at V_VERSION_2,
# _ut_write_working_v); an at-target box (killed AFTER migrate) has BOTH applied →
# max == V_VERSION_2 (mirrors c-rollback-resurrection-arc.sh's same-B at-target assert).
[ "$DBMAX" = "${V_VERSION_2}" ] || { echo "✗ box is not at-target: db.migration max=$DBMAX, expected V2=${V_VERSION_2} (V1+V2 both applied — the kill is AFTER migrate)" >&2; exit 1; }
HEAD_NOW=$(box_head)
[ "$HEAD_NOW" = "$B_FULL" ] || { echo "✗ git HEAD=$HEAD_NOW, expected B ($B_FULL) — the binary/tree must be at target for AtTarget" >&2; exit 1; }
echo "  ✓ at-target crash: in_progress, flag present, db.migration max=$DBMAX (V1+V2), HEAD==B"

# ── TRUNCATE the flag → corrupt (real machinery manipulation) ──
echo ""
echo "── truncating the flag file (real corruption — a partial write the corrupt-flag reader must reject) ──"
FLAG_BYTES_BEFORE=$(VM_EXEC bash -c "wc -c < ~/statbus/$FLAG_PATH 2>/dev/null" | tr -d ' \r\n' || echo "0")
# Cut it to a partial byte count → invalid JSON (a genuine truncation, not an empty file).
VM_EXEC bash -c "truncate -s 24 ~/statbus/$FLAG_PATH"
FLAG_BYTES_AFTER=$(VM_EXEC bash -c "wc -c < ~/statbus/$FLAG_PATH 2>/dev/null" | tr -d ' \r\n' || echo "?")
[ "$FLAG_BYTES_AFTER" = "24" ] || { echo "✗ flag truncation did not land (bytes=$FLAG_BYTES_AFTER, wanted 24; was $FLAG_BYTES_BEFORE)" >&2; exit 1; }
VM_EXEC bash -c "cd ~/statbus && python3 -c 'import json,sys; json.load(open(\"$FLAG_PATH\"))' 2>/dev/null" && { echo "✗ the truncated flag is still valid JSON — corruption not achieved" >&2; exit 1; } || true
echo "  ✓ flag truncated to 24 bytes (was $FLAG_BYTES_BEFORE) — no longer parseable JSON"

# ── recovery boot: start the daemon → corrupt-reader removes the flag → self-heal ──
echo ""
echo "── starting the daemon (recovery boot): corrupt-flag reader removes it, completeInProgressUpgrade converges the orphan ──"
SINCE=$(arm_since)
vm_start_unit "$UPGRADE_UNIT"

echo ""
echo "── assert the REAL corrupt-flag reader fired (this arc's real-path genesis, absent in the fabricated scenario) ──"
CORRUPT_WAIT_START=$(date +%s)
while true; do
    [ "$(journal_has "FLAG_CORRUPT: upgrade flag file unreadable" "$SINCE")" = "yes" ] && { echo "  ✓ journal: FLAG_CORRUPT … removing (recoverFromFlag rejected + removed the truncated flag)"; break; }
    [ $(( $(date +%s) - CORRUPT_WAIT_START )) -lt 180 ] || { echo "✗ the corrupt-flag reader never fired (no FLAG_CORRUPT line) within 180s" >&2; exit 1; }
    sleep 3
done

echo ""
echo "── assert convergence: row → completed, error NULL, [completed-from-in-progress], flag absent, data intact, NRestarts bounded ──"
CONV_START=$(date +%s)
while true; do
    ST=$(row_state_for "$B_FULL")
    [ "$ST" = "completed" ] && { echo "  ✓ row converged to 'completed' (t+$(( $(date +%s) - CONV_START ))s)"; break; }
    case "$ST" in failed|rolled_back) echo "✗ row reached terminal '$ST' instead of the flagless self-heal 'completed'" >&2; exit 1 ;; esac
    [ $(( $(date +%s) - CONV_START )) -lt "$CONVERGE_BUDGET_S" ] || { echo "✗ row did not converge to 'completed' within ${CONVERGE_BUDGET_S}s (last state '$ST')" >&2; exit 1; }
    sleep 5
done
CONV_ERR=$(row_error_for "$B_FULL")
[ -z "$CONV_ERR" ] || { echo "✗ error is not NULL after the self-heal: '$CONV_ERR'" >&2; exit 1; }
[ "$(journal_has "upgrade row [completed-from-in-progress]" "$SINCE")" = "yes" ] || { echo "✗ journal lacks completeInProgressUpgrade's own [completed-from-in-progress] label — the self-heal did not converge THIS row" >&2; exit 1; }
[ "$(flag_present)" = "no" ] || { echo "✗ a flag file is present after the self-heal — the corrupt flag must have been removed and never re-created" >&2; exit 1; }
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 2
echo "  ✓ completed + error NULL, [completed-from-in-progress] logged, flag absent, data intact, NRestarts bounded"

# ── assert SERVING (STATBUS-192 serve-proof) — the RED→GREEN oracle ──
# The kill fired BEFORE Step 11 (StartServices), so the orphan's app is DOWN. A
# serve-proven completeInProgressUpgrade must have brought the app set up + passed the
# app health gate BEFORE writing 'completed'. On pre-fix code the row goes 'completed'
# while the app never started → this assert FAILS (RED). With STATBUS-192 → GREEN.
echo ""
echo "── assert SERVING (STATBUS-192): the self-heal started services + health-gated before 'completed' ──"
assert_health_passes "$VM_NAME"

# ── assert the READ-ONLY WINDOW was lifted BY THE TAIL (STATBUS-192 refinement 1) ──
# Two-part discriminator (a write probe alone can't tell the arms apart — pre-fix, the
# boot backstop clearStaleReadOnlyWindow runs right AFTER completeInProgressUpgrade and
# clears the window, so a probe would be green on BOTH arms):
#   (a) NEGATIVE journal assert — the backstop 'STATBUS-163 BACKSTOP' must be ABSENT in
#       the arm window. Its firing is defined as an investigation trigger; its silence
#       proves the tail lifted the window ITSELF (the right mechanism, refinement 1).
#   (b) write-probe BELT — a fresh psql session must accept a write (no read_only 25006),
#       proving the operator-visible truth (box accepts writes) regardless of mechanism.
#       BEGIN/UPDATE(0-row still trips read-only)/ROLLBACK keeps the box byte-identical;
#       NOT a temp table (temp writes are ALLOWED under read-only → illusory).
echo ""
echo "── assert refinement 1: the tail lifted the read-only window itself (backstop silent) + box accepts writes ──"
[ "$(journal_has "STATBUS-163 BACKSTOP" "$SINCE")" = "no" ] || { echo "✗ boot backstop 'STATBUS-163 BACKSTOP' fired in the arm window — the serve-proof tail did NOT lift the read-only window itself (refinement 1 regressed)" >&2; exit 1; }
echo "  ✓ no STATBUS-163 BACKSTOP in the arm window — the tail lifted the window itself"
WRITE_PROBE=$(VM_EXEC bash -c "cd ~/statbus && printf 'BEGIN;\nUPDATE public.system_info SET value = value;\nROLLBACK;\n' | ./sb psql 2>&1" || true)
if echo "$WRITE_PROBE" | grep -qiE "read_only_sql_transaction|read-only transaction|25006"; then
    echo "✗ write probe hit read-only (25006) — the window is still ON after completion (refinement 1 did not lift it):" >&2
    echo "$WRITE_PROBE" >&2
    exit 1
fi
echo "  ✓ write probe accepted (BEGIN/UPDATE/ROLLBACK, no 25006) — the box serves writes"

echo ""
echo "PASS: flagless-selfheal-at-target — a REAL at-target upgrade crash + a REAL flag truncation produced the [at-target in_progress row + no flag] orphan (the corrupt-flag reader removed the truncated flag, row untouched), and the SAME boot's completeInProgressUpgrade SERVE-PROVENLY converged it to 'completed' (services started + app health gate passed + maintenance off BEFORE the completed write; error NULL, [completed-from-in-progress] logged), flag absent, data intact, no restart loop, the box SERVES (assert_health_passes with a real Host header — the STATBUS-192 oracle), and the read-only window was lifted BY THE TAIL (no STATBUS-163 BACKSTOP; a fresh write is accepted with no 25006 — refinement 1). The fabricated 4-flagless-selfheal-at-target scenario's state now has a run-proven real-path producer — it deletes, and fabricate_resume_state drops one caller."
