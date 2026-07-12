#!/bin/bash
# Arc: postswap-after-commit-kill  (STATBUS-071 §9(5) / doc-017 §3 — 5d CAT-C)
#
# The "after-commit-before-recorded" cell of the migrate commit↔record boundary,
# driven the REAL way (no fabrication): install A → register/schedule B(=working-V)
# via the Albania mechanism → the daemon's applyPostSwap migrate COMMITS V's tx
# (the fixture table) then PARKS at inject.StallHere (migrate.go:845,
# "upgrade-service-parent-killed-after-commit-before-recorded") in the ~ms window
# AFTER the tx commit, BEFORE the db.migration ledger INSERT. The harness SIGKILLs
# the daemon during that stall → V is COMMITTED-but-UNRECORDED. Recovery (systemd
# restart → recoverFromFlag → resumePostSwap; HasPending=true since the ledger row
# is missing → NO self-heal) re-runs migrate.Up → re-applies V → "relation already
# exists" → migrate FAILS → postSwapFailure → rollback → restoreDatabase → the row
# converges to 'rolled_back' (the rune shape). Replaces the FABRICATE-based legacy
# 3-postswap-migrate-killed-after-commit (which abandoned real kill-timing as flaky;
# the StallHere site makes the window a reliable stall, and B=working-V is a real
# pending delta — so both legacy fragilities are gone).
#
# DETERMINISM (doc-017 §3, load-bearing): rolled_back is deterministic ONLY if the
# re-apply RELIABLY conflicts. The existing working-V is `CREATE TABLE
# public.upgrade_arc_fixture` (NO IF NOT EXISTS) → NON-IDEMPOTENT → re-apply errors
# "already exists". So NO construct change — the existing else-branch working-V IS
# the non-idempotent fixture this cell needs. (Contrast mid-tx, where the rollback
# of the uncommitted tx lets the same V re-apply CLEANLY → completed.)
#
# READINESS DETECTION (custom — NOT wait_for_inject_stall_ready): that helper polls
# for a `/sb migrate up` SUBPROCESS (wedge-helpers.sh:366), which does NOT exist on
# the daemon-inline executeUpgrade path (migrate runs IN the daemon). The
# StallHere(:845) parks the DAEMON after V's tx commits, so we detect the
# committed-but-unrecorded stall STATE directly: the fixture table EXISTS (V
# committed) AND db.migration max is still baseline (V unrecorded).
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-after-commit-kill}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
STALL_WAIT_S="${STALL_WAIT_S:-300}"            # budget to reach the after-commit stall
RECOVER_BUDGET_S="${RECOVER_BUDGET_S:-600}"    # budget for autonomous recovery → rolled_back
INPROGRESS_BUDGET_S="${INPROGRESS_BUDGET_S:-300}"
INJECT_CLASS="upgrade-service-parent-killed-after-commit-before-recorded"
RELEASE_FILE="/tmp/arc-after-commit-release"
FIXTURE_TABLE="public.upgrade_arc_fixture"

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

# _dump_postswap_after_commit_kill_failure_diagnostics — STATBUS-155 rider
# (mirrors postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics):
# on ANY non-zero exit, pull B's own upgrade progress log + the daemon journal
# + its row state to STDERR BEFORE _arc_cleanup removes the release marker /
# inject drop-in and cleanup_vm reaps the VM, so a red run is self-sufficient
# without needing a kept VM. Best-effort throughout (|| true) — a diagnostics
# failure must never mask the real assertion error that triggered this trap.
_dump_postswap_after_commit_kill_failure_diagnostics() {
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

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_postswap_after_commit_kill_failure_diagnostics; fi; _arc_cleanup; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-after-commit-kill  (doc-017 §3 — committed-but-unrecorded → rolled_back)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  V=${V_VERSION}  inject=${INJECT_CLASS}"
echo "════════════════════════════════════════════════════════════════"

row_state()     { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
table_exists()  { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT (to_regclass('$FIXTURE_TABLE') IS NOT NULL);\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
migration_max() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version),0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare; register B(=working-V, non-idempotent) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
BASELINE_MAX_VERSION=$(migration_max)
echo "  baseline db.migration max_version: $BASELINE_MAX_VERSION"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

# ── arm the after-commit StallHere via dropin + RESTART the unit (before scheduling) ──
arc_install_stall_dropin "$INJECT_CLASS" "$RELEASE_FILE"

echo ""
echo "── schedule B (daemon runs it → backup → swap → applyPostSwap migrate → V commits → StallHere :845) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

echo ""
echo "── waiting for B → in_progress ──"
arc_wait_row_state "$B_FULL" "in_progress" "$INPROGRESS_BUDGET_S"
NRESTARTS_BASELINE=$(arc_nrestarts)   # post the dispatch reset-failed (service.go:3926)
echo "  baseline NRestarts (post-claim): $NRESTARTS_BASELINE"

# ── CUSTOM readiness: detect the committed-but-unrecorded stall STATE directly ──
echo ""
echo "── waiting for the after-commit stall (fixture table committed AND db.migration unbumped = V unrecorded) ──"
elapsed=0; STALL_OK=0
while [ "$elapsed" -lt "$STALL_WAIT_S" ]; do
    TBL=$(table_exists); MX=$(migration_max); ST=$(row_state)
    if [ "$TBL" = "t" ] && [ "$MX" = "$BASELINE_MAX_VERSION" ] && [ "$ST" = "in_progress" ]; then
        echo "  ✓ after-commit stall engaged at t+${elapsed}s: $FIXTURE_TABLE committed, db.migration still=$MX (V unrecorded), row in_progress"
        STALL_OK=1; break
    fi
    [ $((elapsed % 20)) -eq 0 ] && echo "    [t+${elapsed}s] table=$TBL db.migration=$MX (baseline=$BASELINE_MAX_VERSION) row=$ST"
    sleep 5; elapsed=$((elapsed + 5))
done
[ "$STALL_OK" = "1" ] || { echo "✗ after-commit stall never engaged within ${STALL_WAIT_S}s (table=$TBL db.migration=$MX baseline=$BASELINE_MAX_VERSION row=$ST) — V did not commit-then-park (dropin/restart/inject-site failed)" >&2; exit 1; }

# ── SIGKILL the daemon during the stall → V left COMMITTED-but-UNRECORDED ──
echo ""
echo "── SIGKILL the upgrade-service parent during the after-commit stall (V committed, ledger INSERT not yet run) ──"
# STATBUS-021 / U1 fix: SIGKILL the daemon's CURRENT systemd MainPID (captured FRESH
# — it survives the exit-42 handoff respawn that made the old pgrep'd/captured PID
# stale, so the SIGKILL no longer hits 'No such process') and CONFIRM the death BEFORE
# releasing. arc_kill_confirmed aborts loudly on a miss → the release below runs ONLY
# on a confirmed kill (releasing after a miss manufactured the U1 false 'completed').
arc_kill_confirmed "$VM_NAME" daemon-mainpid || exit 1

# Remove the release file + dropin so the AUTONOMOUS recovery re-run does NOT re-park
# (the StallHere needs the release file; gone → re-run proceeds to the conflict).
echo "── removing the inject release file + dropin (recovery re-run must not re-stall) ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE; rm -f ~/.config/systemd/user/${ARC_UPGRADE_UNIT}.d/inject.conf; systemctl --user daemon-reload 2>/dev/null" || true

# ── autonomous recovery: systemd restart → recoverFromFlag → re-apply → conflict → rollback → rolled_back ──
echo ""
echo "── waiting for autonomous recovery → rolled_back (re-apply conflicts → rollback → restore) ──"
arc_wait_row_state "$B_FULL" "rolled_back" "$RECOVER_BUDGET_S"

echo ""
echo "── convergence checks (deterministic rolled_back — the rune shape) ──"
# CONTRACT: the rollback restored the pre-upgrade snapshot — the orphan fixture
# table (committed by V after the backup) must be GONE (faithful restore, not hollow).
ORPHAN=$(table_exists)
[ "$ORPHAN" = "f" ] || { echo "✗ faithful-restore: $FIXTURE_TABLE still present after rollback (orphan=$ORPHAN) — DB not actually restored (hollow rolled_back)" >&2; exit 1; }
echo "  ✓ orphan $FIXTURE_TABLE gone — the pre-upgrade snapshot was actually restored"

# CONTRACT: V was NOT recorded (rolled back, not forward-completed).
POST_MAX=$(migration_max)
[ "$POST_MAX" = "$BASELINE_MAX_VERSION" ] || { echo "✗ db.migration max changed ($BASELINE_MAX_VERSION → $POST_MAX) — V was recorded; expected rolled-back-to-baseline" >&2; exit 1; }
echo "  ✓ db.migration max back at baseline ($POST_MAX) — V unrecorded (rolled back, not forward-completed)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "$ARC_UPGRADE_UNIT" "$((NRESTARTS_BASELINE + 3))"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: postswap-after-commit-kill (V committed-but-unrecorded → SIGKILL → autonomous re-apply CONFLICTS → rollback → rolled_back; orphan restored away; data intact; healthy)"
