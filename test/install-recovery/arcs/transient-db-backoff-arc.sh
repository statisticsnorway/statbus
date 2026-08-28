#!/bin/bash
# Arc: transient-db-backoff  (STATBUS-071 coverage map — the DB-unreachable
# transient-backoff leg; STATBUS-109 doc-022; architect-ruled 2026-07-15).
#
# WHAT THIS PROVES (AC#1): during a crash-recovery pass, a TRANSIENT db-unreachable
# blip is retried QUIETLY IN-PROCESS (recoverFromFlag's classify-then-act +
# backoffRetry) — never exit-restart noise — with the resolves-vs-exhausts branch
# pair the standard arcs never exercise:
#   • RESOLVES arm: the DB returns within the budget → the backoff clears → the
#     re-read sees ObservedAlreadyAtNew → the resume runs FORWARD to state=completed.
#   • EXHAUST arm: the DB NEVER returns — STATBUS-305: despite this file's own
#     name, this arm tests PERMANENT loss, not a transient one; say so plainly so
#     the next reader is not misled by "transient-db-backoff" into expecting the
#     db to come back here too. The budget exhausts, and the daemon PARKS rather
#     than rolling back — it refuses to restore a backup over a database it
#     cannot verify is actually gone (vs. merely paused, or a severed proxy, or
#     a slow start: from outside the db these are indistinguishable, and a
#     forced restore that guessed wrong would write a backup OVER LIVE DATA,
#     the corruption pathway wearing a recovery costume). This arm originally
#     asserted "rolled_back" — written before the STATBUS-039/111/159 family
#     settled that PARKING is the data-safe terminal for an unverifiable
#     database; the assertion below is doctrine catching up with the arc, not
#     carelessness (STATBUS-305).
# Both arms: NRestarts BOUNDED (the in-process backoff never burns an exit-restart
# cycle), data intact.
#
# THE MECHANISM (service.go recoverFromFlag, Phase=NewSbUpgrading classify-then-act):
# verifyUpgradeObservedStateEx → ObservedPositionUnreadable + CauseDBUnreachable →
# backoffRetry(dbUnreachableSpec) (reconnect+SELECT-1 probe, self-heartbeating) →
# cleared: re-read + dispatch the resolved verdict / exhausted: recoveryRollback.
#
# CONSTRUCTION (real-path, environment manipulation of real machinery state):
#   • The recovery pass reads the DB unreachable only in a sub-second Go-internal
#     window (EnsureDBUp+connect precede the verify). We stall there via the
#     sanctioned inject hook `stalled-before-resuming-verify`, `docker compose pause
#     db` (the DB is genuinely unreachable — a real transient blip), release the
#     stall so the verify sees CauseDBUnreachable, then `unpause` (resolve) or leave
#     it paused past the budget (exhaust). STATBUS_RECOVERY_BACKOFF_BUDGET=60s arms
#     the budget in seconds (production default 5m).
#   • RESOLVES base = an AT-TARGET crash: kill after migrations, before completion
#     (`killed-by-system-after-migrations-before-completion`) → the crashed flag is
#     Phase=NewSbUpgrading, ledger at on-disk max ⇒ the post-backoff re-read is
#     AlreadyAtNew ⇒ FORWARD completion.
#   • EXHAUST base = the container-restart crash (Behind) — the exhaust arm PARKS
#     regardless of the natural state (the backoff never clears, and the db stays
#     unreachable for the rest of the run — see STATBUS-305 above).
# EXHAUST is run FIRST (STATBUS-305: leaves the box PARKED, alive-idle, db still
# paused — no longer "rolls back to A"), then RESOLVES (completes to B) — each on
# its own fresh crashed base (crash_at registers+schedules a NEW upgrade row
# regardless of the prior row's terminal state); the box ends at B. NOTE: this
# is the first run where ARM 1 leaves a PARKED (not rolled_back) predecessor row
# behind ARM 2's own crash_at — ARM 1 has never completed successfully in this
# campaign, so ARM 2 starting from a parked (rather than rolled-back) box is
# untested; worth watching on the first live re-run this fix earns.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH (working lineage — no construct
# spec; reuses the shared working B). VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-transient-db-backoff}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
STALL_WAIT_BUDGET_S="${STALL_WAIT_BUDGET_S:-300}"
BACKOFF_BUDGET="${BACKOFF_BUDGET:-60s}"   # STATBUS_RECOVERY_BACKOFF_BUDGET armed in the recovery dropin
ROW_WAIT_BUDGET_S="${ROW_WAIT_BUDGET_S:-600}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

UPGRADE_UNIT="statbus-upgrade@statbus.service"
STALL_RELEASE_FILE="/tmp/arc-db-backoff-stall.release"

_dump_db_backoff_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (rows + journal + df + docker) ══════════" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, commit_sha, recovery_attempts, error FROM public.upgrade ORDER BY id DESC LIMIT 6;\" | ./sb psql -x" >&2 || true
    echo "── daemon journal ($UPGRADE_UNIT, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && docker compose ps --format 'table {{.Name}}\t{{.Status}}' 2>&1 | head" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_db_backoff_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: transient-db-backoff  (db-unreachable in-process backoff — resolves + exhausts)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  backoff-budget=${BACKOFF_BUDGET}"
echo "════════════════════════════════════════════════════════════════"

# ── local helpers ────────────────────────────────────────────────────────────
row_state_for() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$1' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }
row_error_for() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(error,'') FROM public.upgrade WHERE commit_sha = '$1' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d '\r' || echo "?"; }
# journal_has <plain-substr> <since> — yes|no: did the daemon journal SINCE <since>
# contain <substr>? ARM-SCOPED (grep -F, no quotes/$ in substr): the unit journal
# PERSISTS across restarts, so an unscoped grep in arm 2 would match arm 1's markers
# (e.g. the stall marker → pause the DB while arm 2 is still in its pre-hook phase →
# boot failure). <since> is each arm's VM-local start clock, so every wait is
# deterministic per arm regardless of history (and stays correct if a 3rd arm is added).
journal_has() { VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --since \"$2\" --no-pager 2>/dev/null | grep -qF \"$1\" && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
# journal_count_since <plain-substr> <since> — how many times has the daemon
# journal SINCE <since> contained <substr>? STATBUS-305: used to prove the
# 299 connect-retry loop is genuinely ADVANCING (multiple distinct sub-attempt
# lines), not merely present once — a single match could be a stale fluke;
# a count ≥ 2 is the loop actually cycling. Same ARM-SCOPING as journal_has.
journal_count_since() { VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --since \"$2\" --no-pager 2>/dev/null | grep -cF \"$1\" || true" 2>/dev/null | tr -d ' \r\n' || echo "0"; }
# wait_for_journal_count <substr> <min_count> <budget_s> <since> — poll
# (arm-scoped) until <substr> has appeared at least <min_count> times.
wait_for_journal_count() {
    local marker="$1" min_count="$2" budget="$3" since="$4" start elapsed n
    start=$(date +%s)
    while true; do
        n=$(journal_count_since "$marker" "$since")
        [[ "$n" =~ ^[0-9]+$ ]] || n=0
        if [ "$n" -ge "$min_count" ]; then
            echo "  ✓ journal shows '${marker}' ${n} time(s) (≥ ${min_count}, t+$(( $(date +%s) - start ))s) — the loop is advancing, not stalled on one attempt"
            return 0
        fi
        elapsed=$(( $(date +%s) - start ))
        if [ "$elapsed" -ge "$budget" ]; then
            echo "✗ journal showed '${marker}' only ${n} time(s) within ${budget}s (wanted ≥ ${min_count}) — the connect-retry loop does not look like it is advancing" >&2
            return 1
        fi
        sleep 5
    done
}
db_pause()   { VM_EXEC bash -c "cd ~/statbus && docker compose pause db"   >/dev/null 2>&1 && echo "  ✓ db container PAUSED (unreachable)"   || { echo "✗ docker compose pause db failed" >&2; exit 1; }; }
db_unpause() {
    local out
    out=$(VM_EXEC bash -c "cd ~/statbus && docker compose unpause db 2>&1") && { echo "  ✓ db container UNPAUSED (reachable)"; return 0; }
    # Surface docker's OWN stderr so a future unpause red names the real reason
    # (not-paused / no-such-container / recreated) instead of a bare "failed".
    echo "✗ docker compose unpause db failed: ${out}" >&2; exit 1
}
remove_stall() { VM_EXEC bash -c "rm -f ${STALL_RELEASE_FILE}"; echo "  ✓ stall release file removed — recovery proceeds to the verify"; }

# wait_for_stall — poll the daemon journal for the stall marker (StallHere prints it
# the instant it blocks at the hook, AFTER EnsureDBUp+connect+schema-skew — so the
# DB is up for all pre-hook work; pausing now is correctly post-hook). Deterministic,
# not a guess-timed sleep.
STALL_MARKER="INJECT: stalling at"
# arm_since — the VM's own clock RIGHT NOW (the anchor for this arm's journal waits).
# VM-local, no cross-host skew.
arm_since() { VM_EXEC bash -c "date '+%Y-%m-%d %H:%M:%S'" 2>/dev/null | tr -d '\r'; }
# wait_for_stall <since> — poll (arm-scoped) for the stall marker.
wait_for_stall() {
    local since="$1" start elapsed
    start=$(date +%s)
    while true; do
        [ "$(journal_has "$STALL_MARKER" "$since")" = "yes" ] && { echo "  ✓ recovery reached the stall hook (t+$(( $(date +%s) - start ))s)"; return 0; }
        elapsed=$(( $(date +%s) - start ))
        [ "$elapsed" -lt "$STALL_WAIT_BUDGET_S" ] || { echo "✗ recovery did not reach the stall hook within ${STALL_WAIT_BUDGET_S}s" >&2; exit 1; }
        sleep 3
    done
}
# wait_for_journal <marker> <budget_s> <since> — poll (arm-scoped) for a journal
# marker (backoff engaged / cleared / exhausted).
wait_for_journal() {
    local marker="$1" budget="$2" since="$3" start elapsed
    start=$(date +%s)
    while true; do
        [ "$(journal_has "$marker" "$since")" = "yes" ] && { echo "  ✓ journal shows: ${marker} (t+$(( $(date +%s) - start ))s)"; return 0; }
        elapsed=$(( $(date +%s) - start ))
        [ "$elapsed" -lt "$budget" ] || { echo "✗ journal never showed '${marker}' within ${budget}s" >&2; exit 1; }
        sleep 3
    done
}
# crash_at <inject_class> — bring a fresh crashed Phase=NewSbUpgrading flag into being
# by inline-dispatching B daemon-down with the given kill inject. Leaves the daemon
# DOWN, the flag on disk, flock free.
crash_at() {
    local inject_class="$1"
    echo ""
    echo "── crash base: register+schedule B daemon-down, dispatch with STATBUS_INJECT_AT=${inject_class} ──"
    VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -5" || true
    # Wait for the candidate to verify READY while the daemon is still UP — the
    # daemon's discovery is what flips the row's images-status to ready.
    # arc_schedule_daemon_down (below) STOPS the daemon, so a down-daemon inline
    # dispatch would honestly REFUSE ("images not yet verified ready", STATBUS-187
    # hard-fail, exit 1) and the kill inject would never fire. Proven pattern:
    # postswap-between-migrations-kill-arc.sh / rollback-kill-arc.sh.
    wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
    arc_schedule_daemon_down "$B_FULL"
    arc_install_dispatch_with_inject "$inject_class"
    # The kill must have FIRED: inject.KillHere is os.Exit(137). A different exit
    # (0=completed, 1=refused/precondition) means the inject never fired — fail HERE
    # with the true cause, one step before the flag check.
    [ "$ARC_DISPATCH_RC" = "137" ] || { echo "✗ dispatch exit was $ARC_DISPATCH_RC, expected 137 (KillHere SIGKILL semantics) — the kill inject '${inject_class}' did not fire (non-137 = the dispatch refused or completed, not a crash)" >&2; exit 1; }
    VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null 2>&1 || { echo "✗ no crashed flag after the kill — the inject did not leave a resumable flag" >&2; exit 1; }
    echo "  ✓ crashed flag present (Phase=NewSbUpgrading), flock free, daemon down"
}
# arm_recovery_stall — install the stall dropin (+ 60s backoff budget) and START the
# daemon → the recovery boot stalls at the hook.
arm_recovery_stall() {
    arc_install_stall_dropin "stalled-before-resuming-verify" "$STALL_RELEASE_FILE" "STATBUS_RECOVERY_BACKOFF_BUDGET=${BACKOFF_BUDGET}"
}

# ── A: install + prepare + snapshot ──────────────────────────────────────────
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ═══════════════════ ARM 1 — EXHAUST (Behind base → PARKED, never rolled back) ═══════════════════
echo ""
echo "════════ ARM 1: EXHAUST — DB PERMANENTLY unreachable → budget exhausts → PARKED (STATBUS-305: never rolled_back, restoring over unverifiable state is forbidden) ════════"
crash_at "killed-by-system-during-container-restart"
NR_BEFORE_EXHAUST=$(arc_nrestarts)
ARM_SINCE=$(arm_since)   # anchor this arm's journal waits at the VM clock BEFORE the recovery boot
arm_recovery_stall
wait_for_stall "$ARM_SINCE"
db_pause
remove_stall
# The verify now reads CauseDBUnreachable; assert the backoff ENGAGED in-process.
wait_for_journal "recovery backoff-retry [db-unreachable]" 120 "$ARM_SINCE"
echo "── leaving the DB paused past the ${BACKOFF_BUDGET} budget → the backoff must EXHAUST ──"
wait_for_journal "did not clear within the retry budget" 180 "$ARM_SINCE"
# STATBUS-305: do NOT touch the db container after the exhaust marker, and do
# not expect the daemon to either. Do NOT re-read demo data via a live query
# here (assert_demo_data_counts_match_snapshot, row_error_for, and
# arc_wait_row_state all go through ./sb psql — every one of them would sit
# querying the exact database this arm keeps unreachable for the rest of the
# run; that IS the run-3 red's mechanism (29391895536) one layer up, and it is
# why the original 'rolled_back within 600s' assertion timed out reading '?'
# for the full budget rather than failing fast). The database this arm never
# releases is not a resource the arm — or the daemon — may touch again once
# parked: STATBUS-111 already ruled restore-reattempt human-gated via
# ./sb install, never the auto service. Every observable below comes from the
# journal or systemd, neither of which needs the db.
echo "── assert EXHAUST terminal (STATBUS-305 — the doctrine, not the stale 'rolled_back' expectation): PARKED, connect loop still trying, restarts bounded, and the property that actually matters — NO restore attempted over unverifiable state ──"
wait_for_journal "is PARKED (park state UNKNOWN" 60 "$ARM_SINCE"
[ "$(journal_has "refusing to restore on an unverified row" "$ARM_SINCE")" = "yes" ] || { echo "✗ the PARKED line did not carry the unverified-row refusal reasoning — see the full journal above" >&2; exit 1; }
echo "  ✓ row PARKED, refusing to restore on an unverified row (STATBUS-039/111/159: never destroy state under uncertainty)"
# 299's own heartbeat: the connect loop must be genuinely CYCLING, not stalled
# after one attempt — a count, not a single yes/no, so a stuck loop that only
# ever logged attempt 1 cannot pass by accident.
wait_for_journal_count "Database connect attempt" 2 150 "$ARM_SINCE"
# THE NEGATIVE ASSERTION (the ruling's sharpening, load-bearing): checked LAST,
# after the longest possible elapsed journal window above, so it has the most
# opportunity to catch a real regression. Every positive check above (parked,
# alive-idle, bounded restarts, still trying) would ALSO pass for a future
# build that restored blindly and then parked anyway — assert the invariant
# itself, not its side effects. The restore-start log line is unambiguous
# (exec.go's progress.Write("Restoring database from backup at %s...")) —
# its absence across this whole arm is the actual proof nothing was destroyed.
[ "$(journal_has "Restoring database from backup at" "$ARM_SINCE")" = "no" ] || { echo "✗ 'Restoring database from backup at' appeared in the journal — a restore was attempted over a database this arm never made reachable. That is the data-corruption pathway STATBUS-039 forbids, regardless of what state the row ends up in." >&2; exit 1; }
echo "  ✓ NO restore was ever attempted over the unverifiable database — the invariant holds, not just its side effects"
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 2
NR_AFTER_EXHAUST=$(arc_nrestarts)
echo "  ✓ EXHAUST arm: budget exhausted → PARKED (never rolled_back — that write needs the db this arm keeps down; doctrine, not a stale expectation), unit alive-idle, NRestarts ${NR_BEFORE_EXHAUST}→${NR_AFTER_EXHAUST} bounded (STATBUS-298: one arc now guards both the retry-loop and the restart-loop pathology), connect loop demonstrably still trying, NO blind restore — data is safe because nothing ever touched it"

# ═══════════════════ ARM 2 — RESOLVES (at-target base → forward completion) ═══════════════════
echo ""
echo "════════ ARM 2: RESOLVES — DB returns within budget → backoff clears → FORWARD completion ════════"
crash_at "killed-by-system-after-migrations-before-completion"
NR_BEFORE_RESOLVE=$(arc_nrestarts)
ARM_SINCE=$(arm_since)   # fresh anchor for arm 2 — never matches arm 1's persisted markers
arm_recovery_stall
wait_for_stall "$ARM_SINCE"
db_pause
remove_stall
# The verify reads CauseDBUnreachable; assert the backoff engaged, then RESOLVE it.
wait_for_journal "recovery backoff-retry [db-unreachable]" 120 "$ARM_SINCE"
echo "── DB returns WITHIN the budget → unpause → the backoff clears → re-read AlreadyAtNew → forward ──"
db_unpause
wait_for_journal "recovery backoff-retry [db-unreachable]: cleared" 120 "$ARM_SINCE"
echo "── assert RESOLVES terminal: state=completed (forward), NRestarts bounded, data intact ──"
arc_wait_row_state "$B_FULL" "completed" "$ROW_WAIT_BUDGET_S"
NR_AFTER_RESOLVE=$(arc_nrestarts)
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 2
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_health_passes "$VM_NAME"
echo "  ✓ RESOLVES arm: transient blip retried in-process → cleared → FORWARD completion (state=completed), NRestarts ${NR_BEFORE_RESOLVE}→${NR_AFTER_RESOLVE} bounded, flag gone, data intact, healthy"

echo ""
echo "PASS: transient-db-backoff — the recovery classify-then-act's in-process db-unreachable backoff proven on BOTH arms end to end: EXHAUST (DB PERMANENTLY unreachable → budget exhausts → PARKED, refusing to restore over unverifiable state, connect loop still trying — STATBUS-305) and RESOLVES (DB returns within budget → backoff clears → at-target re-read → forward completion). NRestarts bounded on both (no exit-restart noise — the in-process backoff sits in front of the systemd backstop, STATBUS-109 AC#4; STATBUS-298: EXHAUST now guards both the retry-loop and the restart-loop pathology), data intact throughout (EXHAUST proves this by NEVER TOUCHING the data, not by re-reading it — the db it would need to read stays down by design)."
