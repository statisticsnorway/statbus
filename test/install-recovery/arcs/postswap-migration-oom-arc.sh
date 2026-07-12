#!/bin/bash
# Arc: postswap-migration-oom  (STATBUS-096 — recover from a real, running
# migration killed by an external SIGKILL to Postgres, reproducing the
# OS-OOM-killer EFFECT deterministically without exhausting memory).
#
# TERMINAL FLIPPED TO rolled_back (mechanic, 2026-07-08, STATBUS-145 slice 4 —
# ruled content: STATBUS-145 comment #2's atomicity-flip trace + comment #6's
# "OOM (terminal flip = mechanic's, lands with slice 4)"). This SUPERSEDES the
# prior "completes forward" reshape: that reshape was correct for the PRE-145
# geometry (boot-migrate-up applied the full delta unconditionally, so a
# revived db always got a fresh, clean re-attempt of the SAME migration and
# converged forward). Under 145's minimal-boot-migrate geometry the delta no
# longer runs at boot at all — it runs EXACTLY ONCE, inside applyPostSwap's
# guarded pipeline step (3.5) — so "at-target" is now decided by
# verifyUpgradeObservedStateEx's db.migration-vs-on-disk-max comparison BEFORE
# any forward re-attempt is even considered, and a migration killed mid-run
# (uncommitted, never recorded) reads POSITIVELY BEHIND on the very next live
# pass. Behind + pre-completion is the DESIGNED disposition: one-shot,
# data-safe snapshot restore (STATBUS-039) — never a second forward attempt.
# The delta ran ONCE.
#
# CONSTRUCTION RULING (unchanged — STATBUS-096 comment #1, architect,
# 2026-07-07): real memory pressure is FORBIDDEN as a trigger (the harness VM
# is a CX23, 2 vCPU / 4 GB shared with the whole stack — the kernel
# OOM-killer picks its victim by heuristics there and can take the daemon or
# sshd instead of postgres, exactly the flaky class this suite forbids). The
# ruled trigger: `docker compose kill` on the db service at a
# pg_stat_activity-confirmed midpoint of a real, running migration — the
# postmaster dies by SIGKILL exactly as under the OOM-killer, uncommitted
# work is lost, WAL recovery runs on the next start. The property under test
# ("when the OS OOM-kills Postgres mid-migration, the box recovers") is fully
# exercised without ever touching memory limits.
#
# Single-phase arc (A→B only, no C/fixed phase — this differs from
# working-arc.sh / failing-arc.sh, same shape as ceiling-arc.sh): there is no
# "fix" to apply — the rollback IS the terminal; the box is restored to its
# pre-upgrade clean slate and the operator re-triggers deliberately.
#
# V_sleep migration: `SELECT pg_sleep(60);` + a fixture table (CREATE TABLE +
# INSERT, AFTER the sleep — ORDERING IS LOAD-BEARING, see below), hand-authored
# WITHOUT its own BEGIN/END (construct_upgrade_target's oom spec must not wrap
# it in a DO $$ block — a bare top-level statement is what the midpoint poll
# below expects to see as pg_stat_activity's active query; it ALSO means psql
# autocommits each statement separately, so killing mid-sleep — BEFORE the
# CREATE TABLE/INSERT statements are ever reached — leaves the fixture table
# never created at all: the clean-slate fingerprint match below is the
# stronger, sufficient proof of that, no separate fixture-absence check
# needed). 60s, NOT 3600s: kept short so the arc's own wall-clock stays
# bounded regardless of path (unlike ceiling, nothing here has an internal
# ceiling forcing an early kill).
#
# MECHANICS VERIFIED AGAINST SHIPPED CODE UNDER THE 145 GEOMETRY (mechanic,
# 2026-07-08; STATBUS-145 comment #2's own trace, applied to this arc's
# specific external-kill-of-the-whole-container construction) — read this
# before touching the NRestarts bound or the terminal-wait budget below:
#
#   1. Migrations for a FRESH (non-crash) upgrade are NO LONGER applied by
#      Run()'s boot-migrate-up step — under 145 that step is bounded `--to
#      DaemonSchemaFloor` (service.go:~1934) and V_sleep (a real delta,
#      strictly above the floor) is untouched by it; boot-migrate-up is a
#      no-op here. V_sleep runs EXACTLY ONCE, inside applyPostSwap's own
#      migrate call at the guarded pipeline step 3.5 (service.go:~5467) —
#      the SAME single site STATBUS-095's ceiling and STATBUS-046's
#      park-on-first classification already live at. THIS is where V_sleep
#      is running when the kill lands.
#   2. THE KILL — `docker compose kill -s SIGKILL db` — takes down the WHOLE
#      db container (postmaster + every backend, including the migrate
#      subprocess's), unlike ceiling's ctx-deadline SIGKILL of just the
#      in-container psql backend (db stays up and reachable throughout
#      ceiling's kill). `./sb migrate up`'s subprocess loses its connection
#      mid-run → returns a non-deterministic (classUnknown) exit — no
#      "already exists"/SQLSTATE-53 exit code, just a dead connection — so
#      applyPostSwap's failure handler (service.go:~5506) does NOT classify
#      it as parksOnFirst; it routes to postSwapFailure instead (service.go:
#      5050).
#   3. POSTSWAPFAILURE'S FIRST READ IS UNVERIFIABLE, NOT YET BEHIND: at the
#      instant postSwapFailure calls verifyUpgradeObservedStateEx, the db
#      container we JUST killed is not yet revived (EnsureDBUp only runs at
#      the TOP of the NEXT boot pass, not mid-applyPostSwap) — so the read is
#      ObservedPositionUnreadable, NOT ObservedCannotReachNew. postSwapFailure
#      treats unreadable the SAME as already-at-new: destroying state under
#      uncertainty is forbidden (STATBUS-039) — it records a NON-terminal
#      failure ("observed state is unverifiable...NOT restoring (forward
#      retry on the next recovery pass)") and returns an error. That error
#      propagates up through Run() and the process EXITS (a genuine crash
#      exit, not the planned exit-42 handoff) → systemd restarts it — this
#      is restart #2 (restart #1 was the planned post-claim handoff).
#   4. THE SECOND LIVE PASS IS WHERE ROLLBACK FIRES: on this restart,
#      EnsureDBUp (service.go:~1808, unconditional on every boot) revives the
#      db container fresh. Floor-migrate is again a no-op. recoverFromFlag →
#      resumePostSwap: HasPending is TRUE (V_sleep never committed, never
#      recorded) → the self-heal canary does NOT short-circuit (STATBUS-145
#      slice 2's dependents audit: "never short-circuits a delta-pending
#      resume") → the Resuming arm's OWN observed-state read runs FIRST, on a
#      now-reachable db, with V_sleep genuinely absent from db.migration →
#      ObservedCannotReachNew (positively Behind) → d.rollback() — NOT a
#      second applyPostSwap/migrate attempt. THE ATOMICITY FLIP: V_sleep is
#      never re-attempted; the rollback fires from the Resuming arm's own
#      gate, before the pipeline migrate step is ever reached again. rollback()
#      restores the pre-upgrade snapshot, marks the row rolled_back, clears
#      the flag, restarts containers to the OLD version, and unconditionally
#      os.Exit(75)s at the end (the rc.67 trifecta, true of every rollback()
#      call, identical to ceiling's own terminal exit) — restart #3, this one
#      planned (rollback's own designed conclusion).
#
#   CONSEQUENCE FOR THIS FILE'S ASSERTIONS: NRestarts bound is 4 (a generous
#   ceiling over the 3-restart path derived above — handoff + the unverifiable
#   forward-retry crash-exit + rollback's own terminal exit — with headroom;
#   NOT the load-bearing claim: the actual observed value is logged explicitly).
#   The terminal itself (rolled_back, V-unrecorded, clean-slate fingerprint
#   match) IS load-bearing — mirrors ceiling-arc.sh's own rollback apparatus,
#   adapted for the extra unverifiable-forward-retry pass this arc's
#   whole-container kill introduces (ceiling's kill never takes the db down,
#   so it never needs that extra pass).
#
#   NOT BUILT HERE (explicitly out of scope, pre-blessed but gated): a
#   RECURRING-OOM variant — re-arm the kill at each new pg_stat_activity
#   midpoint. Under 145 this no longer has an on-cue same-step-twice/budget
#   park construction either (same reasoning doc-029 traced for the park
#   rebuild: pre-delta deaths now hit the atomicity flip on their VERY FIRST
#   occurrence, so there is no "twice" to accumulate against). Deliberately
#   left as a separate, King-flagged question (071 coverage-map wording) —
#   do not build it as part of this ticket.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION,
#   SB_ARC_TRUSTED_SIGNER. No C_FULL/C_BRANCH — single-phase arc. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-postswap-migration-oom}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-2400}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
MIDPOINT_WAIT_BUDGET_S="${MIDPOINT_WAIT_BUDGET_S:-300}"
KILL_CONFIRM_BUDGET_S="${KILL_CONFIRM_BUDGET_S:-60}"
BACKOFF_MARKER_WAIT_BUDGET_S="${BACKOFF_MARKER_WAIT_BUDGET_S:-300}"

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
echo "  Arc: postswap-migration-oom  (STATBUS-096 — external SIGKILL of Postgres mid-migration; STATBUS-145 rollback geometry)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

# row_state — TRANSPORT-AWARE (the ruling's explicit requirement): the DB is
# deliberately dying in this arc, so a psql failure must read as "unknown /
# still settling", NEVER as a state verdict. Every caller below treats
# "(db-down/?)" as "keep waiting", not as a terminal or a park.
row_state() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
row_error() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(error,'') FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d '\r' || echo ""; }

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# Baseline fingerprint (post-A + demo data) — THIS arc's terminal is now
# rolled_back (the atomicity flip), so the failing/ceiling-arc apparatus
# applies verbatim: the rollback must restore this byte-for-byte.
echo "── capturing baseline clean-slate fingerprint (post-A) ──"
BASELINE_FP=$(capture_db_fingerprint baseline)
echo "  baseline fingerprint: $BASELINE_FP"

# ─────────────────────────────────────────────────────────────────────────
# Register + schedule B — real Albania path (register + schedule; the daemon
# claims and runs executeUpgrade on its own). Mirrors arc_to's own register/
# schedule steps verbatim (arc-helpers.sh); NOT calling arc_to itself because
# its monolithic wait loop has no hook for the midpoint kill below.
# ─────────────────────────────────────────────────────────────────────────
echo ""
dump_daemon_state "before B"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
echo "── register B ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
dump_signing_diagnostics "$B_FULL"
echo "── schedule B (DB trigger → daemon claims + runs executeUpgrade) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

# ─────────────────────────────────────────────────────────────────────────
# MIDPOINT (anti-vacuity): poll pg_stat_activity for the active pg_sleep
# backend — the proven pattern from the park/mid-tx arcs (the pg_sleep waiter
# originated in the retired 3-postswap-resume-died-parked; live park proof is
# now postswap-health-park-arc.sh), no LISTEN
# client needed. Confirms V_sleep is GENUINELY running (not merely scheduled)
# before the kill — the kill-landed leg starts from a known-good state.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for V_sleep to be ACTIVE in pg_stat_activity (budget ${MIDPOINT_WAIT_BUDGET_S}s) ──"
MID_START=$(date +%s)
while :; do
    ELAPSED=$(( $(date +%s) - MID_START ))
    COUNT=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND query LIKE 'SELECT pg_sleep(60)%';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
    if [ "$COUNT" -ge 1 ] 2>/dev/null; then
        echo "  ✓ V_sleep active in pg_stat_activity after ${ELAPSED}s"
        break
    fi
    if [ "$ELAPSED" -ge "$MIDPOINT_WAIT_BUDGET_S" ]; then
        echo "✗ V_sleep never showed active in pg_stat_activity within ${MIDPOINT_WAIT_BUDGET_S}s — migration did not reach the expected midpoint" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT pid, state, query FROM pg_stat_activity WHERE datname = current_database();\" | ./sb psql -t -A" >&2 || true
        exit 1
    fi
    sleep 3
done

# ─────────────────────────────────────────────────────────────────────────
# THE KILL: docker compose kill -s SIGKILL db — targets the db SERVICE (not
# a hardcoded container name, which varies by compose project naming), same
# signal semantics as the OS OOM-killer delivering SIGKILL to the postmaster.
# No real memory pressure anywhere in this arc (the CX23 VM sharing 4 GB with
# the whole stack makes the kernel's own OOM-killer non-deterministic — it
# can take the daemon or sshd instead of postgres; that flaky class is
# exactly what this construction avoids).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── KILL: docker compose kill -s SIGKILL db (reproducing the OOM-killer's effect on Postgres) ──"
VM_EXEC bash -c "cd ~/statbus && docker compose kill -s SIGKILL db"

echo "── confirming the db container is observed dead (budget ${KILL_CONFIRM_BUDGET_S}s) ──"
KILL_START=$(date +%s)
while :; do
    ELAPSED=$(( $(date +%s) - KILL_START ))
    RUNNING=$(VM_EXEC bash -c "cd ~/statbus && docker compose ps --status running --format '{{.Name}}' db" 2>/dev/null | tr -d '\r' || echo "")
    if [ -z "$RUNNING" ]; then
        echo "  ✓ db container observed dead after ${ELAPSED}s (docker compose ps --status running: empty)"
        break
    fi
    if [ "$ELAPSED" -ge "$KILL_CONFIRM_BUDGET_S" ]; then
        echo "✗ db container still reports running ${KILL_CONFIRM_BUDGET_S}s after the kill (${RUNNING}) — SIGKILL did not land" >&2
        exit 1
    fi
    sleep 2
done

# ─────────────────────────────────────────────────────────────────────────
# BEST-EFFORT OBSERVATION LEGS (per the ruling: stay best-effort, not
# load-bearing — the terminal assertion below is the arc's real claim).
# Under the 145 geometry the kill lands at the pipeline migrate step (3.5),
# not boot-migrate-up, so the OLD "STATBUS-017 fall-through" marker (which
# only fires when boot-migrate-up itself fails) no longer applies to this
# construction — replaced by postSwapFailure's own "unverifiable...forward
# retry" line (MECHANICS point 3), the first pass's actual disposition.
# STATBUS-109's db-unreachable backoff-retry marker (MECHANICS point 4's
# Resuming-arm read) may still fire for a beat if EnsureDBUp is still racing
# on the second pass — kept as a second best-effort leg.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── watching for best-effort recovery markers (budget ${BACKOFF_MARKER_WAIT_BUDGET_S}s) ──"
MARKER_START=$(date +%s)
UNVERIFIABLE_SEEN="no"
BACKOFF_SEEN="no"
while :; do
    ELAPSED=$(( $(date +%s) - MARKER_START ))
    JOURNAL_TAIL=$(VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 400 2>/dev/null" || echo "")
    if [ "$UNVERIFIABLE_SEEN" = "no" ] && echo "$JOURNAL_TAIL" | grep -q 'observed state is unverifiable'; then
        UNVERIFIABLE_SEEN="yes"
        echo "  ✓ postSwapFailure's unverifiable/forward-retry line observed after ${ELAPSED}s (first pass: db down mid-failure-read, non-terminal)"
    fi
    if [ "$BACKOFF_SEEN" = "no" ] && echo "$JOURNAL_TAIL" | grep -q 'recovery backoff-retry \[db-unreachable\]'; then
        BACKOFF_SEEN="yes"
        echo "  ✓ STATBUS-109 db-unreachable backoff-retry marker observed after ${ELAPSED}s"
    fi
    CUR_STATE=$(row_state)
    if [ "$CUR_STATE" = "completed" ] || [ "$CUR_STATE" = "rolled_back" ] || [ "$CUR_STATE" = "failed" ]; then
        echo "  [OBSERVE] row reached terminal '$CUR_STATE' — stopping the marker watch (unverifiable_seen=$UNVERIFIABLE_SEEN backoff_seen=$BACKOFF_SEEN)"
        break
    fi
    if [ "$ELAPSED" -ge "$BACKOFF_MARKER_WAIT_BUDGET_S" ]; then
        echo "  [OBSERVE] marker watch budget (${BACKOFF_MARKER_WAIT_BUDGET_S}s) elapsed before a terminal — continuing to the terminal-state wait regardless (best-effort legs, not load-bearing)"
        break
    fi
    sleep 5
done
echo "  markers observed: unverifiable-forward-retry=$UNVERIFIABLE_SEEN, STATBUS-109 backoff-retry=$BACKOFF_SEEN"

# ─────────────────────────────────────────────────────────────────────────
# TERMINAL: wait for the row to reach a terminal state. Transport-aware
# throughout (row_state already tolerates a dead DB); budget is generous —
# per the mechanics note, this involves the db container's own restart
# window PLUS a genuine daemon crash-restart cycle (the first pass's
# unverifiable non-terminal failure) before the second pass's Resuming-arm
# observed-state read fires the rollback.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for B to reach a terminal state (budget ${UPGRADE_BUDGET_S}s) ──"
TERM_START=$(date +%s)
FINAL_STATE=""
while :; do
    ELAPSED=$(( $(date +%s) - TERM_START ))
    if [ "$ELAPSED" -ge "$UPGRADE_BUDGET_S" ]; then
        echo "✗ B: no terminal state within ${UPGRADE_BUDGET_S}s" >&2
        VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, commit_sha, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
        exit 1
    fi
    STATE=$(row_state)
    case "$STATE" in
        completed|failed|rolled_back) FINAL_STATE="$STATE"; echo "  B: state='$STATE' (t+${ELAPSED}s)"; break ;;
    esac
    sleep 5
done

echo ""
echo "── convergence checks (the box rolled back autonomously from a real SIGKILL of Postgres mid-migration) ──"
[ "$FINAL_STATE" != "completed" ] || { echo "✗ state='completed' — impossible under the 145 atomicity flip (V_sleep was SIGKILLed uncommitted; the Resuming arm's observed-state read must find it positively Behind, never re-attempt it forward)" >&2; exit 1; }
[ "$FINAL_STATE" = "rolled_back" ] || { echo "✗ B reached '$FINAL_STATE', expected 'rolled_back'" >&2; VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 3;\" | ./sb psql" >&2 || true; exit 1; }
echo "  ✓ state='rolled_back'"
echo "  error: $(row_error)"

# V UNRECORDED (flipped from the forward story's V-recorded check): the
# killed migration's transaction died uncommitted with its backend — it must
# never have reached db.migration.
MROWS_B=$(migration_row_count)
[ "$MROWS_B" = "0" ] || { echo "✗ V_sleep left a ledger row (count=$MROWS_B, want 0) — rollback did not unrecord it" >&2; exit 1; }
echo "  ✓ V_sleep not recorded in db.migration (rolled back, transaction died uncommitted with its backend)"

assert_fingerprint_matches "post-rollback == post-A" "$BASELINE_FP" baseline
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

# NRestarts: see MECHANICS points 3-4 for the full derivation. Bound = 4 (a
# generous ceiling over the derived 3-restart path — handoff + the
# unverifiable forward-retry crash-exit + rollback's own terminal exit — with
# headroom) but is NOT the load-bearing claim — the actual observed value is
# logged explicitly so a real run tells us which path fired and lets the
# bound be tightened later.
OBSERVED_NRESTARTS=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  [OBSERVE] NRestarts = ${OBSERVED_NRESTARTS} (3 expected: handoff + unverifiable-forward-retry crash-exit + rollback's own terminal exit; anything higher is a finding)"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 4

echo ""
echo "PASS: postswap-migration-oom (a real, running migration was SIGKILLed via its db container mid-sleep, reproducing the OS-OOM-killer effect deterministically; under the STATBUS-145 atomicity flip the box rolled back autonomously — V_sleep never re-attempted, restored to a byte-identical clean slate — data intact, healthy)"
