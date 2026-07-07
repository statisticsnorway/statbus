#!/bin/bash
# Arc: after-commit-before-recorded-kill  (STATBUS-071 §9(5) / doc-017 §3 — 5d CAT-C, Layer 0)
#
# The SUBPROCESS variant of the "after-commit-before-recorded" cell.
# install A → register/schedule B(=working-V, non-idempotent) → the daemon's
# applyPostSwap spawns `./sb migrate up` (subprocess); the subprocess COMMITS
# V's migration tx (the fixture table) then PARKS at inject.StallHere
# (migrate.go:844, "migrate-subprocess-killed-after-commit-before-recorded") in
# the ~ms window AFTER the tx commit, BEFORE the db.migration ledger INSERT.
# The harness SIGKILLs the migrate SUBPROCESS only — the parent daemon stays
# alive. The parent's runCommandToLog(migrate) returns the subprocess's
# kill-signal error; applyPostSwap calls postSwapFailure → ground truth check
# → GroundTruthBehind (V committed but unrecorded = HasPending=true) → rollback
# → restoreDatabase (snapshot restore, V's effects erased) → os.Exit(75).
# Systemd restarts the daemon; the restarted daemon boots clean (no flag, no
# pending migrations, no uncommitted state). Terminal: row=rolled_back.
#
# Layer 0 in-process recovery: the SAME daemon process that ran applyPostSwap
# handles the rollback WITHOUT a prior systemd restart — only the subprocess
# dies. The parent daemon exits via os.Exit(75) after completing rollback, so
# exactly ONE systemd restart follows (contrast: the parent-kill arc requires
# TWO restarts: SIGKILL + post-recovery rollback exit-75).
#
# DETERMINISM (doc-017 §3, load-bearing): rolled_back is deterministic ONLY if
# the re-apply RELIABLY conflicts. The existing working-V is `CREATE TABLE
# public.upgrade_arc_fixture` (NO IF NOT EXISTS) → NON-IDEMPOTENT → snapshot
# restore removes the fixture table → db.migration has no V entry → boot-migrate
# finds nothing pending. Rollback is clean, no re-wedge.
#
# READINESS DETECTION (custom — same as postswap-after-commit-kill-arc.sh): the
# stall fires IN the migrate subprocess (migrate.go:844); `wait_for_inject_stall_ready`
# also works here (pgrep /sb migrate up finds the subprocess), but the custom
# state check is preferred for consistency: fixture table EXISTS (V committed)
# AND db.migration max is still baseline (V unrecorded).
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-after-commit-subprocess-kill}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
STALL_WAIT_S="${STALL_WAIT_S:-300}"            # budget to reach the after-commit stall
RECOVER_BUDGET_S="${RECOVER_BUDGET_S:-600}"    # budget for autonomous Layer 0 recovery → rolled_back
INPROGRESS_BUDGET_S="${INPROGRESS_BUDGET_S:-300}"
INJECT_CLASS="migrate-subprocess-killed-after-commit-before-recorded"
RELEASE_FILE="/tmp/arc-after-commit-subprocess-release"
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
trap 'rc=$?; _arc_cleanup; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: after-commit-before-recorded-kill  (doc-017 §3 — Layer 0 subprocess kill)"
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
echo "── schedule B (daemon runs it → backup → swap → applyPostSwap migrate → V commits → StallHere :844) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

echo ""
echo "── waiting for B → in_progress ──"
arc_wait_row_state "$B_FULL" "in_progress" "$INPROGRESS_BUDGET_S"
NRESTARTS_BASELINE=$(arc_nrestarts)   # post the dispatch reset-failed (service.go:3926)
echo "  baseline NRestarts (post-claim): $NRESTARTS_BASELINE"

# ── CUSTOM readiness: detect the committed-but-unrecorded stall STATE directly ──
# The migrate subprocess (./sb migrate up under applyPostSwap) stalls at
# migrate.go:844 AFTER V's tx commits. Custom detection: fixture table EXISTS
# (V committed) AND db.migration max still = baseline (V unrecorded).
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

# ── SIGKILL the migrate SUBPROCESS (NOT the daemon parent) → V left COMMITTED-but-UNRECORDED ──
# The subprocess cmdline is /home/statbus/statbus/sb migrate up --verbose
# (service.go:4751 runCommandToLog); pgrep -nf '/sb migrate up' matches it.
echo ""
echo "── SIGKILL the migrate subprocess during the after-commit stall (V committed, ledger INSERT not yet run) ──"
# STATBUS-021 / U1 fix: capture the migrate-subprocess PID FRESH at kill time and
# CONFIRM it is dead BEFORE releasing the stall. The old path captured the PID into a
# variable and released the stall unconditionally; a stale-PID miss then let the
# un-killed subprocess finish → a FALSE 'completed'. arc_kill_confirmed aborts loudly
# on a miss, so the release below is reached ONLY on a confirmed kill.
arc_kill_confirmed "$VM_NAME" migrate-subprocess || exit 1

# Remove the release file + dropin so the parent daemon's Layer 0 recovery
# (postSwapFailure → rollback → os.Exit(75)) does not re-stall on exit-75's
# systemd-restart boot path. The restarted daemon's boot-migrate-up finds
# nothing pending (rollback restored the snapshot) and proceeds cleanly.
echo "── removing the inject release file + dropin (recovery path must not re-stall) ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE; rm -f ~/.config/systemd/user/${ARC_UPGRADE_UNIT}.d/inject.conf; systemctl --user daemon-reload 2>/dev/null" || true

# ── Layer 0 autonomous recovery: parent daemon catches subprocess death →
#    postSwapFailure → GroundTruthBehind → rollback → restoreDatabase → os.Exit(75)
#    → systemd restart → daemon boots clean → rolled_back ──
echo ""
echo "── waiting for autonomous Layer 0 recovery → rolled_back (parent handles in-process, then exit-75 → restart → clean boot) ──"
arc_wait_row_state "$B_FULL" "rolled_back" "$RECOVER_BUDGET_S"

echo ""
echo "── convergence checks (deterministic rolled_back — Layer 0 subprocess-kill recovery) ──"
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
# Layer 0: one rollback exit-75 → one systemd restart → clean boot. Allow baseline+3 for headroom.
assert_systemd_restart_counter_bounded "$VM_NAME" "$ARC_UPGRADE_UNIT" "$((NRESTARTS_BASELINE + 3))"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: after-commit-before-recorded-kill (V committed-but-unrecorded → SIGKILL migrate subprocess → parent Layer 0 in-process recovery → rollback → rolled_back; orphan restored away; data intact; healthy)"
