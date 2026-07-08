#!/bin/bash
# Arc: postswap-between-migrations-kill  (STATBUS-071 §9(5) 5d / doc-017 §1 — CAT-C)
#
# TERMINAL FLIPPED TO rolled_back (mechanic, 2026-07-08, STATBUS-145 slice 4 —
# same re-derivation treatment as the OOM/ceiling arcs). SUPERSEDES the prior
# "one-shot KillHere → in-dispatch forward-recovery → completed" premise: that
# premise was written for the PRE-145 geometry, where the inline `./sb install`
# dispatch's OWN re-exec'd boot-migrate carried the FULL delta unbounded, so a
# subprocess kill there was a genuine "half-applied boot-migrate, defer to
# RecoverFromFlag, re-run cleanly" story. Under 145 that boot-migrate step
# (install_upgrade.go:290, STATBUS-145 AC#3) is ALSO bounded `--to
# DaemonSchemaFloor` — V1/V2 are strictly above the floor, so it is a NO-OP:
# the kill site is never reached there at all. The kill now lands INSIDE
# applyPostSwap's own migrate call (service.go:~5467, the SAME single site the
# OOM/ceiling arcs already use) — and that call's failure handler routes
# through `postSwapFailure`'s observed-state gate (STATBUS-039), which reads
# POSITIVELY BEHIND here (V2 missing from db.migration, DB fully reachable
# throughout — see MECHANICS below for why this needs no extra restart pass,
# unlike OOM's whole-container kill) → one-shot rollback, not a forward re-run.
#
# ONE-SHOT KillHere fires inside runUp's loop AFTER migration 1's db.migration
# INSERT succeeds and BEFORE migration 2's runPsqlFile (migrate.go:912,
# killed-by-system-between-migrations). Migration 1 IS recorded and migration 2
# is PENDING at kill time — this is WHY the shared working-V is TWO migrations
# (doc-017 §5 option a): a real "N recorded, N+1 pending" gap, now the exact
# shape verifyUpgradeObservedStateEx reads as positively Behind.
#
# MECHANICS VERIFIED AGAINST SHIPPED CODE UNDER THE 145 GEOMETRY (mechanic,
# 2026-07-08) — read this before touching the terminal assertion or the
# dispatch-exit-code check:
#
#   1. KillHere (cli/internal/inject/inject.go:413) is `os.Exit(137)` — but it
#      fires INSIDE the `sb migrate up` SUBPROCESS applyPostSwap spawns via
#      runCommandToLog, a genuinely separate OS process. The PARENT (the
#      re-exec'd `./sb install` process, now running inside applyPostSwap)
#      is NOT killed — it observes the child's non-zero exit as an ordinary
#      Go error return, exactly like OOM/ceiling's own migrate-failure site.
#   2. Exit code 137 does not match ErrCommandTimeout (that's the ceiling's
#      OWN ctx-deadline SIGKILL, ruled out here) NOR the exit-20/22
#      deterministic/resource classification (STATBUS-046 slice 2) — it is
#      classUnknown, so applyPostSwap's handler (service.go:~5506) routes to
#      `postSwapFailure` (service.go:5050), the SAME site the OOM arc's
#      whole-container kill also reaches.
#   3. UNLIKE OOM, THIS KILL NEVER TOUCHES POSTGRES ITSELF — only the CLIENT
#      `sb migrate up` process self-exits; the db container and its
#      connections are completely undisturbed throughout. So postSwapFailure's
#      FIRST (and only) verifyUpgradeObservedStateEx call finds the DB
#      immediately reachable: db.migration max == V_VERSION (V1 recorded) <
#      on-disk max == V_VERSION_2 (V2 pending) → ObservedCannotReachNew
#      (positively Behind) on the very first read — no extra crash-restart
#      pass is ever needed (contrast OOM, whose whole-container kill makes the
#      first read ObservedPositionUnreadable, needing a second live pass).
#      postSwapFailure's own line (service.go:5070) fires: "Failure after
#      booting the new binary [...]: ... — observed state confirms it's
#      behind the new version (db.migration max version <V1> < on-disk max
#      <V2> (migrations did not run)); auto-restoring from this upgrade's
#      snapshot" — the exact numbers in that parenthetical are THIS arc's own
#      mechanism-true marker, distinguishing it from mid-migration-kill's
#      "max version <baseline> < ..." (neither migration recorded there).
#   4. d.rollback() (called from postSwapFailure) ALWAYS terminates via
#      os.Exit(75) (the rc.67 trifecta) — REGARDLESS of caller context
#      (daemon service or, as here, the one-shot inline `./sb install`
#      process). The dispatch's own visible exit code is therefore 75, NOT
#      the pre-145 story's 0. The whole sequence — pre-swap steps, syscall.Exec
#      into the new binary, its own re-exec'd runCrashRecovery's floor-only
#      no-op boot-migrate, RecoverFromFlag→resumePostSwap→applyPostSwap, the
#      kill, postSwapFailure, rollback, os.Exit(75) — happens inside the SAME
#      single OS process (syscall.Exec preserves the PID) — there is no
#      systemd restart involved anywhere in this arc: the daemon unit was
#      stopped by arc_schedule_daemon_down before dispatch and is NEVER
#      started by this flow (restartUpgradeService, install_upgrade.go, only
#      runs on runInlineUpgradeScheduled's SUCCESS path — unreached here,
#      since os.Exit(75) fires deep inside before that call is ever made). The
#      unit stays exactly as arc_schedule_daemon_down left it — nothing to
#      assert there.
#
# Rides the kill-arc driver (5a) + the ONE-SHOT MARKER (sibling of
# postswap-mid-migration-kill). Load-bearing GREEN proof now: clean-slate
# fingerprint match (rollback restored the pre-upgrade snapshot byte-for-byte)
# + db.migration max reverted to baseline (never advanced past it).
#
# Arc shape (A → B, killed between migrations, rolled back to A's clean slate):
#   A = base_sha   install fresh, pinned; populate; trust the arc signer.
#   B = A + V1+V2  the signed shared WORKING fixture (register; the upgrade target).
#   dispatch       register B → stop daemon + schedule B → touch the one-shot marker
#                  → ./sb install WITH STATBUS_INJECT_AT + the marker → KillHere fires
#                  ONCE in the migrate subprocess between migration 1 and migration 2.
#   in-dispatch    the dispatch SURVIVES the subprocess death but the SAME process's
#   rollback       applyPostSwap reads observed state positively Behind (V2 missing,
#                  db.migration max version < on-disk max) → one-shot rollback →
#                  os.Exit(75) — all within the same ./sb install.
#   GREEN          kill landed (marker consumed) + rc=75 + postSwapFailure's
#                  "confirms it's behind" line naming the exact V1/V2 gap; row
#                  rolled_back; db.migration max == baseline; clean-slate
#                  fingerprint matches A; data intact; flag absent; healthy.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, V_VERSION_2,
# SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-between-migrations-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-between-migrations"
KILL_MARKER="/tmp/arc-killonce-between-migrations"

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
echo "  Arc: postswap-between-migrations-kill  (one-shot KillHere between V1/V2 → STATBUS-145 rollback geometry)"
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
# rolled_back, so the failing/ceiling-arc apparatus applies verbatim: the
# rollback must restore this byte-for-byte.
echo "── capturing baseline clean-slate fingerprint (post-A) ──"
BASELINE_FP=$(capture_db_fingerprint baseline)
echo "  baseline fingerprint: $BASELINE_FP"

echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"

echo "── arming one-shot kill marker ($KILL_MARKER) ──"
VM_EXEC bash -c "touch $KILL_MARKER && ls -la $KILL_MARKER"

# ── SINGLE dispatch — the kill lands inside applyPostSwap's own migrate call;
# the SAME process observes the dead subprocess, reads observed state
# positively Behind, and rolls back — all in one ./sb install invocation. ──
_marker_state() { VM_EXEC bash -c "test -e $KILL_MARKER && echo present || echo consumed" 2>/dev/null | tr -d ' \r\n'; }
arc_install_dispatch_with_inject "$INJECT_CLASS" "$INSTALL_BUDGET_S" "$KILL_MARKER"

echo ""
echo "── verifying the kill landed and the SAME dispatch rolled back (postSwapFailure → rollback → os.Exit(75)) ──"
[ "$(_marker_state)" = "consumed" ] || { echo "✗ one-shot marker still present — KillHere never fired (the between-migrations inject site was not reached)" >&2; exit 1; }
echo "  ✓ one-shot kill landed (marker consumed)"
[ "$ARC_DISPATCH_RC" = "75" ] || { echo "✗ dispatch exited $ARC_DISPATCH_RC, expected 75 — d.rollback() always terminates via os.Exit(75) regardless of caller context (MECHANICS point 4)" >&2; exit 1; }
echo "  ✓ dispatch exited 75 — in-process rollback terminal, not a dead/hung dispatch"
# Mechanism-true marker: postSwapFailure's own "confirms it's behind" line,
# naming the EXACT V1/V2 gap this arc's kill window produces (distinct from
# mid-migration-kill's baseline-vs-V2 gap — see that arc's own marker).
EXPECT_REASON_SUBSTR="db.migration max version ${V_VERSION} < on-disk max ${V_VERSION_2}"
[ "$(arc_dispatch_log_has "auto-restoring from this upgrade's snapshot")" = "yes" ] || { echo "✗ dispatch output missing postSwapFailure's rollback line" >&2; exit 1; }
[ "$(arc_dispatch_log_has "$EXPECT_REASON_SUBSTR")" = "yes" ] || { echo "✗ dispatch output missing the expected observed-state gap ('$EXPECT_REASON_SUBSTR') — wrong kill window, or V1 was not actually recorded before the kill" >&2; exit 1; }
echo "  ✓ path pinned: postSwapFailure's rollback line + the exact V1-recorded/V2-pending gap ($EXPECT_REASON_SUBSTR)"

# ── GREEN: rolled_back + clean-slate restored (max reverted to baseline) ──
echo ""
echo "── convergence checks (rollback restored the pre-upgrade clean slate) ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    rolled_back) echo "  ✓ rollback terminal: rolled_back" ;;
    completed) echo "✗ state='completed' — impossible under the 145 atomicity flip (V2 was never applied; postSwapFailure's observed-state read must find it positively Behind, never forward-complete)" >&2; exit 1 ;;
    *) echo "✗ unexpected terminal state: $FINAL_STATE" >&2; exit 1 ;;
esac
POST_MAX=$(migration_max_version)
[ "$POST_MAX" = "$BASELINE_MAX_VERSION" ] || { echo "✗ db.migration max=$POST_MAX, want baseline=$BASELINE_MAX_VERSION — rollback did not revert past V1" >&2; exit 1; }
echo "  ✓ db.migration max == baseline ($POST_MAX) — V1 unrecorded, rollback restored the clean slate"

assert_fingerprint_matches "post-rollback == post-A" "$BASELINE_FP" baseline
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

# NRestarts: no longer meaningful for this arc under the 145 flip. The daemon
# unit was stopped by arc_schedule_daemon_down before dispatch and is NEVER
# started anywhere in this flow — restartUpgradeService (install_upgrade.go)
# only runs on runInlineUpgradeScheduled's SUCCESS path, unreached here since
# os.Exit(75) fires deep inside applyPostSwap's failure handling, well before
# that call site. (Pre-145 this check was meaningful — the forward-completion
# story DID reach restartUpgradeService — but that story no longer applies.)
# DURABILITY CONDITION: this vacuousness RESTS ON rollback() exiting the
# process (os.Exit(75)) rather than returning — a return-based refactor makes
# runCrashRecovery's deferred restart closure reachable on the failure path
# and RE-ARMS this removed check.

echo ""
echo "PASS: postswap-between-migrations-kill (one-shot kill between V1/V2 → the SAME dispatch's observed-state read found V2 positively missing and rolled back autonomously to a byte-identical clean slate; data intact)"
