#!/bin/bash
# Arc: postswap-mid-migration-kill  (STATBUS-071 §9(5) 5d / doc-017 §1 — CAT-C)
#
# RE-GATED [PENDING-145-REDERIVE] (mechanic, 2026-07-09). TWO static
# derivations of this arc's terminal have now been REFUTED by real runs — no
# third armchair guess. (1) The pre-145 story ("in-dispatch forward recovery
# → completed at attempts==1", run 28837119781) was voided by STATBUS-145's
# floor-only boot-migrate (the delta moved to applyPostSwap). (2) The
# architect's STATBUS-145 slice-2 prediction and the mechanic's independent
# STATBUS-145 re-derivation (both: a mid-delta kill reads observed-state
# positively Behind at applyPostSwap's postSwapFailure site → one-shot
# rollback → os.Exit(75) — see the MECHANICS section below, kept for the
# record, NOT current fact) were BOTH REFUTED by the wave-2 dispatch: the row
# reached `completed` via forward recovery instead. Something in the real
# control flow diverges from both static traces in a way neither predicted.
# The terminal is UNDETERMINED by analysis alone — the next run, single-actor
# and instrumented (STATBUS-148-style progress-log + journal capture wired in
# below, ready for when this arc is un-gated), is what settles it. Until then
# this arc loudly DECLINES to assert a terminal, exits BEFORE any VM is
# provisioned (zero cost). A surviving marker after the next dispatch is
# itself a red flag (STATBUS-145 PIN 3).
#
# ONE-SHOT KillHere fires at the START of runPsqlFile (migrate.go:389,
# killed-by-system-during-individual-migration-execution) — BEFORE migration
# 1's psql even runs, so NOTHING is committed: db.migration stays at baseline
# (neither V1 nor V2 recorded), unlike between-migrations-kill where V1 is
# already recorded at kill time. This is the arc's DISTINGUISHING window from
# its sibling — same kill mechanism (KillHere, os.Exit(137) in the migrate
# CLIENT subprocess only; Postgres itself untouched), same failure classU
# nknown routing — but the REFUTED derivation below assumed that routing
# always lands at postSwapFailure and always reads Behind; the actual run
# says otherwise, and WHERE it actually lands is exactly what the next
# instrumented run must show (which flag phase, which disposition site).
#
# MECHANICS — THE REFUTED STATIC DERIVATION, KEPT FOR THE RECORD (mechanic,
# 2026-07-08 — this reasoning did NOT survive contact with a real run; do
# not trust it as current fact, only as what was ruled out):
#   1. KillHere os.Exit(137)s the migrate CLIENT subprocess only; the parent
#      (the re-exec'd ./sb install process, running inside applyPostSwap)
#      survives and observes the dead subprocess as an ordinary Go error.
#   2. Under 145, applyPostSwap's own unbounded migrate call (service.go:
#      ~5467) is the ONLY site the delta ever runs at — the re-exec'd
#      runCrashRecovery's OWN boot-migrate (install_upgrade.go:290) is bounded
#      `--to DaemonSchemaFloor`, a no-op for V1/V2 (both above floor), so the
#      inject site is never reached there.
#   3. Exit 137 is classUnknown (not ceiling's ErrCommandTimeout, not exit
#      20/22) → routes to postSwapFailure (service.go:5050), which reads
#      observed state IMMEDIATELY (Postgres was never touched by this kill —
#      only the client process died) → db.migration max == BASELINE <
#      on-disk max == V_VERSION_2 → ObservedCannotReachNew (positively
#      Behind) on the first and only read → d.rollback() → os.Exit(75).
#   4. REFUTED: the wave-2 run showed `completed`, not `rolled_back` — this
#      chain's step 3 (or an unstated precondition of it) is wrong. Possible
#      unexamined factors for the next instrumented run to distinguish: a
#      self-heal canary short-circuit this trace didn't account for, a
#      different flag phase than assumed, or the kill landing somewhere other
#      than believed. Read, don't guess again.
#
# STATUS: OBSERVATIONAL, not a proven terminal contract. This arc now RUNS
# (the exit-0 skip is gone) and captures the evidence an instrumented
# single-actor run needs, but a green PASS here does NOT certify which
# terminal is correct — it only means the box ended clean and healthy and the
# OBSERVE lines below were logged. The STATBUS-071 map cell for this arc
# STAYS [PENDING-145-REDERIVE] until the architect reads this run's captured
# evidence (OBSERVE lines + _dump_mid_migration_failure_diagnostics on any
# non-zero exit) and rules on the actual terminal.
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
echo "  Arc: postswap-mid-migration-kill  (one-shot KillHere before V1 → terminal UNDETERMINED, instrumented observation)"
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

# ── OBSERVE, DO NOT ASSERT, the terminal (STATBUS-145 wave-2 ruling — see the
# header): two static derivations were refuted by real runs. Log everything
# the next reviewer needs; enforce nothing about which terminal is "right"
# until an instrumented single-actor run settles it. ──
echo ""
echo "── OBSERVE (not asserted) ──"
echo "  [OBSERVE] dispatch exit code: $ARC_DISPATCH_RC"
FINAL_STATE=$(upgrade_state)
echo "  [OBSERVE] final upgrade row state: $FINAL_STATE"
POST_MAX=$(migration_max_version)
echo "  [OBSERVE] db.migration max version: $POST_MAX (baseline=$BASELINE_MAX_VERSION, V_VERSION_2=$V_VERSION_2)"
echo "  [OBSERVE] postSwapFailure rollback line present: $(arc_dispatch_log_has "auto-restoring from this upgrade's snapshot")"
echo "  [OBSERVE] any observed-state gap text present: $(arc_dispatch_log_has "db.migration max version")"
RECOVERY_ATTEMPTS=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT recovery_attempts FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  [OBSERVE] recovery_attempts: $RECOVERY_ATTEMPTS (>1 would indicate more than one recovery actor raced — see the mid-tx sibling's single-actor finding)"

# Terminal-agnostic sanity: whichever terminal actually occurred, a genuinely
# single-actor, well-behaved run should still end with a clean, healthy box.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS (OBSERVATIONAL ONLY — this reports observations, not a proven terminal; the STATBUS-071 map cell stays [PENDING-145-REDERIVE] until the architect reads the OBSERVE lines above and rules): postswap-mid-migration-kill (one-shot kill before migration 1 landed; the box reached a clean, healthy terminal — WHICH one is logged above for the next reviewer, not enforced here)"
