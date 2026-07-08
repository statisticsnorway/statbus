#!/bin/bash
# Arc: postswap-mid-migration-kill  (STATBUS-071 §9(5) 5d / doc-017 §1 — CAT-C)
#
# RULED (architect, wave 3, run 28980487041): terminal is `completed`
# (forward), PROVEN on a real VM. TWO prior static derivations of this arc's
# terminal (a pre-145 "in-dispatch forward recovery" story, and a STATBUS-145
# re-derivation predicting `rolled_back`) were both REFUTED by real runs before
# this — see MECHANICS below for that history, kept for the record. The
# instrumented single-actor run this arc was rebuilt to produce settled it:
#
#   THE MECHANISM, live: the one-shot KillHere fires inside the
#   crash-recovery's OWN floor-bound boot-migrate (`--to DaemonSchemaFloor`,
#   install_upgrade.go:296) — NOT inside the delta step. That bounded
#   boot-migrate call then fails (exit 137). Captured verbatim in the run:
#     crash recovery: boot migrate up failed but a service-held flag is
#     present (id=2, phase="post_swap") — deferring to RecoverFromFlag
#     (STATBUS-017): exit status 137
#   A service-held flag is present, so STATBUS-017's defer fires instead of
#   aborting crash recovery: RecoverFromFlag runs, and post_swap proceeds
#   forward from there, applying the delta (V1+V2) fresh. recovery_attempts=1
#   (single actor, single pass — this arc dispatches only once).
#
#   This is a PRE-DELTA death: the kill landed before the delta step
#   (applyPostSwap's own migrate call) was ever reached, so there is nothing
#   for the atomicity flip to catch Behind — the delta runs exactly once,
#   cleanly, afterward. Same family as its mid-tx sibling (also a pre-delta
#   death, also completes forward); the OPPOSITE family is between-migrations
#   (a MID-delta death, ledger already advanced → Behind → rolled_back). See
#   the STATBUS-071 map for the full ruled rule stated once, in one place.
#
# ONE-SHOT KillHere fires at the START of runPsqlFile (migrate.go:389,
# killed-by-system-during-individual-migration-execution) — BEFORE migration
# 1's psql even runs, so NOTHING is committed: db.migration stays at baseline
# (neither V1 nor V2 recorded) until the forward recovery pass applies both.
#
# MECHANICS — THE REFUTED STATIC DERIVATIONS, KEPT FOR THE RECORD (mechanic,
# 2026-07-08 — this reasoning did NOT survive contact with a real run; do
# not trust it as current fact, only as what was ruled out before the actual
# mechanism above was found):
#   1. KillHere os.Exit(137)s the migrate CLIENT subprocess only; the parent
#      (the re-exec'd ./sb install process, running inside applyPostSwap)
#      survives and observes the dead subprocess as an ordinary Go error.
#   2. ASSUMED (WRONG): that applyPostSwap's own migrate call (service.go:
#      ~5467) was the ONLY site the delta could run at, so the re-exec'd
#      runCrashRecovery's OWN boot-migrate (install_upgrade.go:290, bounded
#      `--to DaemonSchemaFloor`) was assumed a no-op the kill could never
#      reach. WRONG: the kill DOES land inside that bounded boot-migrate call.
#   3. ASSUMED (WRONG): exit 137 routes to postSwapFailure (service.go:5050),
#      reading observed state immediately → db.migration max == BASELINE <
#      on-disk max == V_VERSION_2 → ObservedCannotReachNew (positively
#      Behind) → d.rollback() → os.Exit(75).
#   4. REFUTED, then EXPLAINED: the wave-2 run showed `completed`, not
#      `rolled_back` — step 2's assumption was the actual error (the kill
#      reaches the bounded boot-migrate, not the unbounded delta step); the
#      real disposition is the STATBUS-017 defer path documented above, not
#      postSwapFailure at all.
#
# Rides the kill-arc driver (5a): daemon-DOWN + ./sb install inline-dispatch +
# the REAL inject + the ONE-SHOT MARKER (arc_install_dispatch_with_inject's 3rd
# arg — the kill fires EXACTLY ONCE). Uses the WORKING lineage's 2-migration
# fixture (V1+V2).
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION, V_VERSION_2,
# SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-mid-migration-kill}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INJECT_CLASS="killed-by-system-during-individual-migration-execution"
KILL_MARKER="/tmp/arc-killonce-mid-migration"
UPGRADE_UNIT="statbus-upgrade@statbus.service"

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

# _dump_mid_migration_failure_diagnostics — STATBUS-148-style rider (mirrors
# postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics): on ANY
# non-zero exit, pull B's own upgrade progress log + the daemon journal to
# STDERR before cleanup_vm reaps the VM, so the NEXT run (which determines
# this arc's true terminal) is self-sufficient without needing a kept VM.
# Best-effort throughout — a diagnostics failure must never mask the real
# assertion error that triggered this trap.
_dump_mid_migration_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (B's progress log + daemon journal) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── B's upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    else
        echo "  (no log_relative_file_path found for B's row — row absent or DB unreachable)" >&2
    fi
    echo "── daemon journal ($UPGRADE_UNIT, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_mid_migration_failure_diagnostics; fi; VM_EXEC bash -c "rm -f $KILL_MARKER 2>/dev/null" 2>/dev/null || true; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: postswap-mid-migration-kill  (one-shot KillHere hits the floor boot-migrate → STATBUS-017 defer → forward → completed)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  inject=${INJECT_CLASS}  V=${V_VERSION}/${V_VERSION_2}"
echo "════════════════════════════════════════════════════════════════"

upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# ── A: install + prepare; register; schedule daemon-down; dispatch with the kill ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
BASELINE_MAX_VERSION=$(migration_max_version)
echo "  baseline db.migration max_version: $BASELINE_MAX_VERSION"

# Baseline fingerprint (post-A + demo data) — captured for the NEXT reviewer's
# comparison; NOT asserted against this round (the terminal is undetermined,
# so there is nothing known-correct to compare it to yet).
echo "── capturing baseline clean-slate fingerprint (post-A, observational) ──"
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

# ── SINGLE dispatch ──
_marker_state() { VM_EXEC bash -c "test -e $KILL_MARKER && echo present || echo consumed" 2>/dev/null | tr -d ' \r\n'; }
arc_install_dispatch_with_inject "$INJECT_CLASS" "$INSTALL_BUDGET_S" "$KILL_MARKER"

echo ""
echo "── verifying the kill landed (mechanism check — valid regardless of terminal) ──"
[ "$(_marker_state)" = "consumed" ] || { echo "✗ one-shot marker still present — KillHere never fired (the mid-migration inject site was not reached)" >&2; exit 1; }
echo "  ✓ one-shot kill landed (marker consumed)"

# ── ASSERT the RULED terminal (architect, wave 3, run 28980487041 — see the
# header): PRE-delta death → STATBUS-017 defer → forward → completed. This is
# no longer an observation; it is the arc's contract. ──
echo ""
echo "── ASSERT the ruled terminal ──"
echo "  dispatch exit code: $ARC_DISPATCH_RC"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
[ "$FINAL_STATE" != "rolled_back" ] || { echo "✗ state='rolled_back' — impossible under the ruled terminal (a pre-delta death must complete forward via the STATBUS-017 defer, never roll back)" >&2; exit 1; }
[ "$FINAL_STATE" = "completed" ] || { echo "✗ B reached '$FINAL_STATE', expected 'completed'" >&2; VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 3;\" | ./sb psql" >&2 || true; exit 1; }
echo "  ✓ state='completed'"

POST_MAX=$(migration_max_version)
echo "  db.migration max version: $POST_MAX (baseline=$BASELINE_MAX_VERSION, V_VERSION_2=$V_VERSION_2)"
[ "$POST_MAX" = "$V_VERSION_2" ] || { echo "✗ db.migration max=$POST_MAX, expected V_VERSION_2=$V_VERSION_2 — the delta did not apply fully forward" >&2; exit 1; }
echo "  ✓ delta applied fully forward (max == V_VERSION_2)"

echo "  asserting the STATBUS-017 defer marker is present (the mechanism, not just the outcome) ──"
[ "$(arc_dispatch_log_has "deferring to RecoverFromFlag (STATBUS-017)")" = "yes" ] || { echo "✗ the STATBUS-017 defer marker is absent from the dispatch log — the ruled mechanism did not fire the way this arc's contract requires" >&2; exit 1; }
echo "  ✓ STATBUS-017 defer marker present (boot migrate up failed but a service-held flag is present → deferring to RecoverFromFlag)"

RECOVERY_ATTEMPTS=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT recovery_attempts FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  [OBSERVE] recovery_attempts: $RECOVERY_ATTEMPTS (ruled single-actor value is 1 — this arc dispatches only once; not hard-asserted here, logged for the next reviewer)"

# Terminal-agnostic sanity, now load-bearing for a KNOWN terminal.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: postswap-mid-migration-kill (one-shot KillHere landed inside the floor-bound boot-migrate, before the delta step; STATBUS-017 deferred to RecoverFromFlag, post_swap ran the delta forward, B reached completed — data intact, healthy, the ruled terminal)"
