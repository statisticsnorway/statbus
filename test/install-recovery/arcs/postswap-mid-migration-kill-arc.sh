#!/bin/bash
# Arc: postswap-mid-migration-kill  (STATBUS-071 §9(5) 5d / doc-017 §1 — CAT-C)
#
# TERMINAL FLIPPED TO rolled_back (mechanic, 2026-07-08, STATBUS-145 slice 4 —
# same re-derivation treatment as postswap-between-migrations-kill, its sibling
# arc; read that file's MECHANICS section for the full trace — this header
# only states the parts that differ for THIS arc's earlier kill window).
#
# ONE-SHOT KillHere fires at the START of runPsqlFile (migrate.go:389,
# killed-by-system-during-individual-migration-execution) — BEFORE migration
# 1's psql even runs, so NOTHING is committed: db.migration stays at baseline
# (neither V1 nor V2 recorded), unlike between-migrations-kill where V1 is
# already recorded at kill time. This is the arc's DISTINGUISHING window —
# same kill mechanism (KillHere, os.Exit(137) in the migrate CLIENT subprocess
# only; Postgres itself untouched), same failure routing (classUnknown →
# postSwapFailure), same terminal (rolled_back, single pass, no extra restart
# needed since the DB stays reachable throughout), but a DIFFERENT observed-
# state gap: "db.migration max version <baseline> < on-disk max <V2>" instead
# of between-migrations' "<V1> < <V2>". Asserting on the EXACT gap text (not
# just the terminal state) is what proves this arc actually exercised its own
# earlier window rather than silently degenerating into its sibling's.
#
# MECHANICS (identical derivation to postswap-between-migrations-kill; see
# that file for the full trace — summary here for this file's own record):
#   1. KillHere os.Exit(137)s the migrate CLIENT subprocess only; the parent
#      (the re-exec'd ./sb install process, running inside applyPostSwap)
#      survives and observes the dead subprocess as an ordinary Go error.
#   2. Under 145, applyPostSwap's own unbounded migrate call (service.go:
#      ~5467) is the ONLY site the delta ever runs at — the re-exec'd
#      runCrashRecovery's OWN boot-migrate (install_upgrade.go:290) is bounded
#      `--to DaemonSchemaFloor`, a no-op for V1/V2 (both above floor), so the
#      inject site is never reached there. The pre-145 "boot-migrate carries
#      the delta" premise this arc's original construction relied on is void.
#   3. Exit 137 is classUnknown (not ceiling's ErrCommandTimeout, not exit
#      20/22) → routes to postSwapFailure (service.go:5050), which reads
#      observed state IMMEDIATELY (Postgres was never touched by this kill —
#      only the client process died) → db.migration max == BASELINE <
#      on-disk max == V_VERSION_2 → ObservedCannotReachNew (positively
#      Behind) on the first and only read → d.rollback() → os.Exit(75).
#   4. No systemd restart anywhere: the daemon unit was stopped by
#      arc_schedule_daemon_down before dispatch and restartUpgradeService
#      (install_upgrade.go, only reached on runInlineUpgradeScheduled's
#      SUCCESS path) is never called — os.Exit(75) fires first. Nothing to
#      assert about that unit.
#
# Rides the kill-arc driver (5a): daemon-DOWN + ./sb install inline-dispatch +
# the REAL inject + the ONE-SHOT MARKER (arc_install_dispatch_with_inject's 3rd
# arg — the kill fires EXACTLY ONCE). Uses the WORKING lineage's 2-migration
# fixture (V1+V2); load-bearing GREEN proof is now the clean-slate fingerprint
# match (rollback restored A byte-for-byte) + db.migration max unchanged from
# baseline (neither migration ever got the chance to apply).
#
# Arc shape (A → B, killed before migration 1, rolled back to A's clean slate):
#   A = base_sha   install fresh, pinned; populate; trust the arc signer.
#   B = A + V1+V2  the signed shared WORKING fixture (register; the upgrade target).
#   dispatch       register B (daemon up) → stop daemon + schedule B → touch the
#                  one-shot marker → ./sb install WITH STATBUS_INJECT_AT + the marker
#                  → KillHere fires ONCE in the migrate subprocess at runPsqlFile start.
#   in-dispatch    the dispatch SURVIVES the subprocess death but the SAME process's
#   rollback       applyPostSwap reads observed state positively Behind (baseline <
#                  on-disk max, migrations did not run) → one-shot rollback →
#                  os.Exit(75) — all within the same ./sb install.
#   GREEN          kill landed (marker consumed) + rc=75 + postSwapFailure's
#                  "confirms it's behind" line naming the baseline/V2 gap; row
#                  rolled_back; db.migration max == baseline; clean-slate
#                  fingerprint matches A; data intact; flag absent; healthy.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, V_VERSION_2,
# SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-mid-migration-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-during-individual-migration-execution"
KILL_MARKER="/tmp/arc-killonce-mid-migration"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"
: "${V_VERSION_2:?V_VERSION_2 required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

trap 'rc=$?; VM_EXEC bash -c "rm -f $KILL_MARKER 2>/dev/null" 2>/dev/null || true; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-mid-migration-kill  (one-shot KillHere before V1 → STATBUS-145 rollback geometry)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS}  V=${V_VERSION}/${V_VERSION_2}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare; register; schedule daemon-down; dispatch with the kill ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
BASELINE_MAX_VERSION=$(migration_max_version)
echo "  baseline db.migration max_version: $BASELINE_MAX_VERSION"

# Baseline fingerprint (post-A + demo data) — this arc's terminal is now
# rolled_back, so the failing/ceiling-arc apparatus applies verbatim.
echo "── capturing baseline clean-slate fingerprint (post-A) ──"
BASELINE_FP=$(capture_db_fingerprint baseline)
echo "  baseline fingerprint: $BASELINE_FP"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"

# Arm the one-shot kill marker (consumed by the FIRST kill; absent for recovery).
echo "── arming one-shot kill marker ($KILL_MARKER) ──"
VM_EXEC bash -c "touch $KILL_MARKER && ls -la $KILL_MARKER"

# ── SINGLE dispatch — the kill lands inside applyPostSwap's own migrate call;
# the SAME process observes the dead subprocess, reads observed state
# positively Behind, and rolls back — all in one ./sb install invocation. ──
_marker_state() { VM_EXEC bash -c "test -e $KILL_MARKER && echo present || echo consumed" 2>/dev/null | tr -d ' \r\n'; }
arc_install_dispatch_with_inject "$INJECT_CLASS" "$INSTALL_BUDGET_S" "$KILL_MARKER"

echo ""
echo "── verifying the kill landed and the SAME dispatch rolled back (postSwapFailure → rollback → os.Exit(75)) ──"
[ "$(_marker_state)" = "consumed" ] || { echo "✗ one-shot marker still present — KillHere never fired (the mid-migration inject site was not reached)" >&2; exit 1; }
echo "  ✓ one-shot kill landed (marker consumed)"
[ "$ARC_DISPATCH_RC" = "75" ] || { echo "✗ dispatch exited $ARC_DISPATCH_RC, expected 75 — d.rollback() always terminates via os.Exit(75) regardless of caller context" >&2; exit 1; }
echo "  ✓ dispatch exited 75 — in-process rollback terminal, not a dead/hung dispatch"
# Mechanism-true marker: postSwapFailure's own "confirms it's behind" line,
# naming the EXACT baseline/V2 gap this arc's EARLIER kill window produces —
# distinct from between-migrations-kill's V1/V2 gap (proves this arc actually
# killed before V1, not merely reproducing its sibling's window).
EXPECT_REASON_SUBSTR="db.migration max version ${BASELINE_MAX_VERSION} < on-disk max ${V_VERSION_2}"
[ "$(arc_dispatch_log_has "auto-restoring from this upgrade's snapshot")" = "yes" ] || { echo "✗ dispatch output missing postSwapFailure's rollback line" >&2; exit 1; }
[ "$(arc_dispatch_log_has "$EXPECT_REASON_SUBSTR")" = "yes" ] || { echo "✗ dispatch output missing the expected observed-state gap ('$EXPECT_REASON_SUBSTR') — wrong kill window, or a migration was unexpectedly recorded before the kill" >&2; exit 1; }
echo "  ✓ path pinned: postSwapFailure's rollback line + the exact baseline/V2 gap ($EXPECT_REASON_SUBSTR)"

# ── GREEN: rolled_back + clean-slate restored (max unchanged from baseline) ──
echo ""
echo "── convergence checks (rollback restored the pre-upgrade clean slate) ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    rolled_back) echo "  ✓ rollback terminal: rolled_back" ;;
    completed) echo "✗ state='completed' — impossible under the 145 atomicity flip (neither migration was ever applied; postSwapFailure's observed-state read must find it positively Behind, never forward-complete)" >&2; exit 1 ;;
    *) echo "✗ unexpected terminal state: $FINAL_STATE" >&2; exit 1 ;;
esac
POST_MAX=$(migration_max_version)
[ "$POST_MAX" = "$BASELINE_MAX_VERSION" ] || { echo "✗ db.migration max=$POST_MAX, want baseline=$BASELINE_MAX_VERSION — rollback did not revert to the clean slate" >&2; exit 1; }
echo "  ✓ db.migration max == baseline ($POST_MAX) — neither migration ever recorded, rollback restored the clean slate"

assert_fingerprint_matches "post-rollback == post-A" "$BASELINE_FP" baseline
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

# NRestarts: not meaningful here under the 145 flip — see MECHANICS point 4
# (the daemon unit is never started anywhere in this flow; os.Exit(75) fires
# well before restartUpgradeService's call site is ever reached).
# DURABILITY CONDITION: rests on rollback() EXITING (os.Exit(75)), not
# returning — a return-based refactor makes runCrashRecovery's deferred
# restart closure reachable on the failure path and RE-ARMS this check.

echo ""
echo "PASS: postswap-mid-migration-kill (one-shot kill before migration 1 → the SAME dispatch's observed-state read found the delta positively missing and rolled back autonomously to a byte-identical clean slate; data intact)"
