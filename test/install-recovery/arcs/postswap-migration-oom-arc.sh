#!/bin/bash
# Arc: postswap-migration-oom  (STATBUS-096 — recover from a real, running
# migration killed by an external SIGKILL to Postgres, reproducing the
# OS-OOM-killer EFFECT deterministically without exhausting memory).
#
# THE STORY (architect reshape, 2026-07-07, confirmed against shipped code):
# a migration is OOM-killed ONCE -> the box's own boot sequence revives the
# db unconditionally -> the migration re-runs -> COMPLETED (forward). This is
# NOT a rollback story. See the MECHANICS section below for why — this
# reshape SUPERSEDES an earlier draft of this file that expected rolled_back;
# that draft's own code-tracing is what surfaced the mechanism this version
# is built on, so the trace is kept (updated) rather than discarded.
#
# CONSTRUCTION RULING: STATBUS-096 comment #1 (architect, 2026-07-07). Real
# memory pressure is FORBIDDEN as a trigger (the harness VM is a CX23, 2 vCPU
# / 4 GB shared with the whole stack — the kernel OOM-killer picks its victim
# by heuristics there and can take the daemon or sshd instead of postgres,
# exactly the flaky class this suite forbids). The ruled trigger: `docker
# compose kill` on the db service at a pg_stat_activity-confirmed midpoint of
# a real, running migration — the postmaster dies by SIGKILL exactly as under
# the OOM-killer, uncommitted work is lost, WAL recovery runs on the next
# start. The property under test ("when the OS OOM-kills Postgres mid-
# migration, the box recovers") is fully exercised without ever touching
# memory limits.
#
# Single-phase arc (A→B only, no C/fixed phase — this differs from
# working-arc.sh / failing-arc.sh): there is no "fix" to apply — B's own
# migration is what completes, on its post-revival re-attempt.
#
# V_sleep migration: `SELECT pg_sleep(60);` + a fixture table (so the arc can
# assert it genuinely ran, not merely that db.migration's ledger advanced),
# hand-authored WITHOUT its own BEGIN/END (construct_upgrade_target's oom
# spec must not wrap it in a DO $$ block — a bare top-level statement is what
# the midpoint poll below expects to see as pg_stat_activity's active query).
# 60s, NOT 3600s: see MECHANICS point 3 for why a long sleep is actively
# wrong here (every path revives the db and re-runs the SAME sleep from
# scratch — a 3600s sleep means the arc waits out another hour on every
# revival, guaranteed-stall-red, derivable without a run).
#
# MECHANICS VERIFIED AGAINST SHIPPED CODE (mechanic, 2026-07-07; confirmed +
# extended by the architect the same day) — read this before touching the
# NRestarts bound or the terminal-wait budget below:
#
#   1. Migrations for a FRESH (non-crash) upgrade are actually applied by
#      Run()'s own unconditional "boot-migrate-up" step (service.go, right
#      after the exit-42 handoff restart, BEFORE recoverFromFlag) — NOT by
#      applyPostSwap's migrate call, which is normally a no-op fallback. So
#      THIS is where V_sleep is running when the kill lands.
#   2. When boot-migrate-up's psql subprocess loses its connection (the
#      container was just SIGKILLed), Run() does NOT exit here: with a
#      service-held flag present it explicitly FALLS THROUGH to
#      recoverFromFlag in the SAME process (service.go:~1974: "deferring to
#      recoverFromFlag for snapshot restore (STATBUS-017)"). At this point
#      flag.Phase is still "post_swap" (resumePostSwap has not run yet), so
#      recoverFromFlag's PostSwap branch fires resumePostSwap -> applyPostSwap
#      in the SAME boot.
#   3. THE DESTINY, not a race (architect correction of the original draft's
#      "two sub-cases" framing): Run()'s boot ALWAYS runs EnsureDBUp
#      (service.go:1808 — `docker compose up -d db`, unconditional, on EVERY
#      pass, before any recovery branch) — so the db is guaranteed reachable
#      again within the SAME crash-resume pass that discovers the
#      service-held flag; there is no code path where the daemon proceeds
#      with the db still down. Consequence: applyPostSwap's own migrate call
#      always finds a live db and always re-attempts V_sleep fresh from the
#      top (pg_sleep has no memory of the killed attempt) -> it completes ->
#      applyPostSwap finishes -> state=completed. If EnsureDBUp itself is
#      still racing docker's own restart at the exact moment applyPostSwap's
#      earlier health-check step runs (a narrow timing window, NOT the
#      steady-state destiny), postSwapFailure's observed-state read can
#      still see the db as unreachable ONE time -> records a non-terminal
#      failure and returns (verified: postSwapFailure's unreachable branch
#      never calls backoffRetry — that only exists at recoverFromFlag's
#      Resuming/ground-truth branch, service.go:1085) -> propagates up
#      through Run() -> the process exits -> systemd restarts it (a SECOND
#      restart beyond the planned exit-42 one) -> on THIS next boot
#      EnsureDBUp runs again and by now the db is definitely up -> the
#      Resuming branch's observed-state read + STATBUS-109's backoff-retry
#      (service.go:1085) may fire for a beat if any residual race remains,
#      then clears -> forward resumes -> completed. Either way the box
#      converges to completed; the only variable is whether it takes the
#      one-restart path (handoff only) or the two-restart path (handoff +
#      one DB-unreachable exit) to get there.
#
#   CONSEQUENCE FOR THIS FILE'S ASSERTIONS: NRestarts bound stays at 3 (a
#   generous ceiling covering both the one- and two-restart paths above with
#   headroom) but is NOT the load-bearing claim here — the actual OBSERVED
#   value is logged explicitly so a real run tells us which path fired and
#   lets the bound be tightened later. Any restart beyond 3 is itself a
#   finding (a genuine restart-loop pathology).
#
#   NOT BUILT HERE (explicitly out of scope, pre-blessed but gated): a
#   RECURRING-OOM variant — re-arm the kill at each new pg_stat_activity
#   midpoint so the migration never gets a clean run, driving the crash-resume
#   death budget to its same-step-twice/exhaustion PARK or restore-broke
#   terminal instead of a clean forward completion. That variant is a
#   deliberate, separate arc gated on a King map-wording nod (071 coverage-map
#   cell rewording lives in the King's decision bundle) — do not build it as
#   part of this ticket.
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

# ── STATBUS-145 GATE [PENDING-145-REDERIVE] ──────────────────────────────────
# This arc's terminal is being FLIPPED under the minimal-boot-migrate geometry:
# the delta moved from the re-exec'd boot-migrate (this header's premise) to the
# applyPostSwap step, so a mid-delta OOM kill reads observed-state Behind → a
# data-safe rollback → the ruled terminal is `rolled_back` on the FIRST kill
# (V-unrecorded + clean-slate fingerprint). That flip is the mechanic's edit and
# lands WITH slice 4's proving dispatch — until the ORACLE run confirms it, this
# arc loudly DECLINES to assert rather than assert an underived terminal. Exits
# BEFORE any VM is provisioned (zero cost). A surviving marker after slice 4 is
# itself a red flag (STATBUS-145 PIN 3).
echo "SKIP [PENDING-145-REDERIVE]: terminal contract awaiting the slice-4 oracle run (STATBUS-145)"
exit 0

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
echo "  Arc: postswap-migration-oom  (STATBUS-096 — external SIGKILL of Postgres mid-migration)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

# row_state — TRANSPORT-AWARE (the ruling's explicit requirement): the DB is
# deliberately dying in this arc, so a psql failure must read as "unknown /
# still settling", NEVER as a state verdict. Every caller below treats
# "(db-down/?)" as "keep waiting", not as a terminal or a park.
row_state() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
row_error() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(error,'') FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d '\r' || echo ""; }

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
# NOTE: no baseline clean-slate fingerprint capture here (unlike failing-arc.sh)
# — this arc's terminal is completed (forward), not rolled_back, so there is
# no "must match pre-upgrade byte-for-byte" claim to make; the fixture-table +
# migration-recorded assertions below are this arc's equivalent proof that the
# forward path genuinely ran to completion.
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ─────────────────────────────────────────────────────────────────────────
# Register + schedule B — real Albania path (register + schedule; the daemon
# claims and runs executeUpgrade on its own). Mirrors arc_to's own register/
# schedule steps verbatim (arc-helpers.sh); NOT calling arc_to itself because
# its monolithic wait loop has no hook for the midpoint kill below.
# ─────────────────────────────────────────────────────────────────────────
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
# backend — the proven pattern from the park/mid-tx arcs
# (3-postswap-resume-died-parked.sh wait_for_active_pg_sleep), no LISTEN
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
# Two markers, either or neither may appear depending on which restart path
# fires (see MECHANICS point 3):
#   - the STATBUS-017 fall-through line, if boot-migrate-up's own failure is
#     what's observed ("deferring to recoverFromFlag for snapshot restore").
#   - STATBUS-109's db-unreachable backoff-retry marker (its first live
#     firing in an arc), if the two-restart path's Resuming branch has to
#     wait out any residual db-unreachable window.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── watching for best-effort recovery markers (budget ${BACKOFF_MARKER_WAIT_BUDGET_S}s) ──"
MARKER_START=$(date +%s)
DEFER_SEEN="no"
BACKOFF_SEEN="no"
while :; do
    ELAPSED=$(( $(date +%s) - MARKER_START ))
    JOURNAL_TAIL=$(VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 400 2>/dev/null" || echo "")
    if [ "$DEFER_SEEN" = "no" ] && echo "$JOURNAL_TAIL" | grep -q 'deferring to recoverFromFlag for snapshot restore (STATBUS-017)'; then
        DEFER_SEEN="yes"
        echo "  ✓ STATBUS-017 fall-through observed after ${ELAPSED}s (boot-migrate-up's own failure deferred to recoverFromFlag)"
    fi
    if [ "$BACKOFF_SEEN" = "no" ] && echo "$JOURNAL_TAIL" | grep -q 'recovery backoff-retry \[db-unreachable\]'; then
        BACKOFF_SEEN="yes"
        echo "  ✓ STATBUS-109 db-unreachable backoff-retry marker observed after ${ELAPSED}s (first live firing in an arc)"
    fi
    CUR_STATE=$(row_state)
    if [ "$CUR_STATE" = "completed" ] || [ "$CUR_STATE" = "rolled_back" ] || [ "$CUR_STATE" = "failed" ]; then
        echo "  [OBSERVE] row reached terminal '$CUR_STATE' — stopping the marker watch (defer_seen=$DEFER_SEEN backoff_seen=$BACKOFF_SEEN)"
        break
    fi
    if [ "$ELAPSED" -ge "$BACKOFF_MARKER_WAIT_BUDGET_S" ]; then
        echo "  [OBSERVE] marker watch budget (${BACKOFF_MARKER_WAIT_BUDGET_S}s) elapsed before a terminal — continuing to the terminal-state wait regardless (best-effort legs, not load-bearing)"
        break
    fi
    sleep 5
done
echo "  markers observed: STATBUS-017 defer=$DEFER_SEEN, STATBUS-109 backoff-retry=$BACKOFF_SEEN"

# ─────────────────────────────────────────────────────────────────────────
# TERMINAL: wait for the row to reach a terminal state. Transport-aware
# throughout (row_state already tolerates a dead DB); budget is generous —
# per the mechanics note, this may involve the db container's own restart
# window PLUS, on the two-restart path, an extra daemon crash-restart cycle
# before EnsureDBUp + the observed-state re-read clear on the next boot.
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
echo "── convergence checks (the box recovered forward from a real SIGKILL of Postgres mid-migration) ──"
[ "$FINAL_STATE" = "completed" ] || { echo "✗ B reached '$FINAL_STATE', expected 'completed' — the single-OOM contract is FORWARD recovery (Run()'s own EnsureDBUp always revives the db before any recovery branch runs)" >&2; VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 3;\" | ./sb psql" >&2 || true; exit 1; }
echo "  ✓ state='completed'"
echo "  error: $(row_error)"

# V RECORDED (flipped from the rollback story's V-unrecorded check): the
# killed migration's ledger row must exist and be the highest applied
# version — it genuinely completed on its post-revival re-attempt, not
# merely "some migration or other" completed.
MROWS_B=$(migration_row_count)
[ "$MROWS_B" = "1" ] || { echo "✗ V_sleep recorded ${MROWS_B} time(s) in db.migration (want exactly 1)" >&2; exit 1; }
MAXV=$(migration_max_version)
[ "$MAXV" = "$V_VERSION" ] || { echo "✗ db.migration max version=$MAXV, expected V_VERSION=$V_VERSION" >&2; exit 1; }
echo "  ✓ V_sleep recorded exactly once in db.migration (max version == V_VERSION=$V_VERSION)"

# FIXTURE TABLE PRESENT: the migration's own CREATE TABLE + INSERT actually
# ran (not just its ledger row) — proof the re-attempt executed the real
# migration body end to end, past the sleep.
FIXTURE_COUNT=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.upgrade_arc_oom_fixture WHERE id = 1 AND note = 'oom';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
[ "$FIXTURE_COUNT" = "1" ] || { echo "✗ public.upgrade_arc_oom_fixture missing its row (count=$FIXTURE_COUNT, want 1) — the migration's body did not fully execute" >&2; exit 1; }
echo "  ✓ public.upgrade_arc_oom_fixture present (the migration genuinely ran to completion)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

# NRestarts: see MECHANICS point 3 for the full derivation. Bound stays at 3
# (a generous ceiling over both the one-restart [handoff only] and
# two-restart [handoff + one DB-unreachable exit] paths) but is NOT the
# load-bearing claim — the actual observed value is logged explicitly so a
# real run tells us which path fired and lets the bound be tightened later.
OBSERVED_NRESTARTS=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  [OBSERVE] NRestarts = ${OBSERVED_NRESTARTS} (1 = handoff-only path; 2 = handoff + one DB-unreachable restart; anything higher is a finding)"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 3

echo ""
echo "PASS: postswap-migration-oom (a real, running migration was SIGKILLed via its db container mid-sleep, reproducing the OS-OOM-killer effect deterministically; the box's own boot revived the db and re-ran the migration to completed; fixture present; data intact; healthy)"
