#!/usr/bin/env bash
# Behavioural contract for stop_running_jobs (proc-tree.sh), used by run-arcs.sh's
# finalize (STATBUS-425 M4 review N1). No wall-clock ceiling: promptness is the
# poll COUNT the function reports, so a loaded host cannot flake it.
#   1. a job that ignores TERM and never finishes is KILLed after CAP polls;
#   2. a job that finishes on its own, DURING the wait, ends the wait at once
#      (polls far below the cap). With `kill -0 %N` as the predicate a finished-
#      but-listed job reads as alive and burns the whole cap (mutant below);
#   3. an already-finished job is not selected, and nothing is signalled.
set -uo pipefail
# Owned-group watchdog (headroom over the real cap: the longest legitimate case waits CAP s
# and there are ~6 such cases). A mutant that never KILLs a TERM-ignoring job makes the
# test non-terminating by design; that is reported as WATCHDOG, not as an assertion failure.
WATCHDOG_S=${WATCHDOG_S:-240}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/install-recovery/lxd/proc-tree.sh"
fails=0
# Re-exec under our OWN process group so the watchdog can stop exactly this test's
# group (and nothing else) if a mutant makes it non-terminating.
if [ -z "${_SRJ_OWNED:-}" ]; then
    export _SRJ_OWNED=1
    set -m
    bash "$0" "$@" &
    child=$!
    set +m
    # descendants of the test process, by walking ppid (its nested scenario scripts
    # run in their own groups, so the group alone would leave them behind).
    _desc() { local p k; for p in "$@"; do for k in $(ps -axo pid=,ppid= | awk -v p="$p" '$2==p{print $1}'); do echo "$k"; _desc "$k"; done; done; }
    ( sleep "$WATCHDOG_S"
      if kill -0 "$child" 2>/dev/null; then
          echo "WATCHDOG: test did not finish in ${WATCHDOG_S}s; stopping ITS OWN group and descendants (NOT an assertion failure)"
          # KILL at once, in the same step: the outer shell kills this watchdog as
          # soon as `wait` returns, so a delayed second step would never run and
          # TERM-ignoring descendants would be left behind.
          tree=$(_desc "$child")
          kill -KILL -- "-$child" 2>/dev/null; kill -KILL $child $tree 2>/dev/null
      fi ) &
    wd=$!
    wait "$child"; rc=$?
    kill "$wd" 2>/dev/null
    exit "$rc"
fi
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }
CAP=${CAP:-12}
run_case() { # name -> prints report lines
    ( set +m
      case "$1" in
        ignoring) ( trap '' TERM; while :; do sleep 0.2; done ) & ;;
        # ignores TERM (so TERM does not end it) but finishes by itself ~2s in: the
        # finished-but-listed shape
        finishes) ( trap '' TERM; sleep 2 ) & ;;
        already)  ( exit 0 ) & sleep 1 ;;
      esac
      stop_running_jobs "$CAP" )
}
out=$(run_case ignoring 2>&1)
echo "$out" | sed 's/^/  ignoring: /'
check "TERM-ignoring job is KILLed after the cap" "$(echo "$out" | grep -c 'killed=1')" 1
check "TERM-ignoring job waited the full cap first" "$(echo "$out" | sed -n 's/.*polls=\([0-9]*\).*/\1/p' | head -1)" "$CAP"

out=$(run_case finishes 2>&1)
echo "$out" | sed 's/^/  finishes: /'
polls=$(echo "$out" | sed -n 's/.*polls=\([0-9]*\).*/\1/p' | sort -n | tail -1)
check "a job finishing during the wait ends it well under the cap (max polls $polls, cap $CAP)" "$([ -n "$polls" ] && [ "$polls" -le 5 ] && echo prompt || echo "polls=$polls")" prompt
check "no KILL for a job that finished by itself" "$(echo "$out" | grep -c 'killed=1')" 0

# 2b. the REAL trigger: stop_running_jobs runs inside a TERM/EXIT trap handler (as
#     finalize does) and the job obeys TERM and dies promptly. There, `kill -0 %N`
#     keeps answering "alive" for the finished job until the handler returns, so
#     with that predicate the poll burns the whole cap. Observed with polls=cap.
# The scenario is written to a FILE and run as `bash file`: measured, the same
# body run through `bash -c "<string>"` does NOT reproduce the finished-but-listed
# reading (the mutant polled 1 there and 8 as a file), so a string harness would
# be a false negative for the very predicate under test.
SCEN=$(mktemp "${TMPDIR:-/tmp}/stop-running-jobs-scen.XXXXXX")
cat > "$SCEN" <<'SCENARIO'
source "$1"
# A trap invokes fin() with NO arguments, so "$2" is empty inside it and the
# helper silently fell back to its 160 s default. Capture the cap in a named
# variable BEFORE the trap and pass that; the fixture also prints it so the
# test can assert the cap actually in force.
SCEN_CAP=$2
echo "fixture-cap=$SCEN_CAP"
( trap "exit 1" TERM; while :; do sleep 0.2; done ) &
fin() { trap - EXIT INT TERM HUP; stop_running_jobs "$SCEN_CAP"; exit 0; }
trap fin EXIT; trap "exit 143" TERM
( sleep 0.5; kill -TERM $$ ) &
while :; do sleep 0.1; done
SCENARIO
out=$(bash "$SCEN" "$ROOT/test/install-recovery/lxd/proc-tree.sh" "$CAP" 2>&1)
rm -f "$SCEN"
check "the trap-handler fixture really passes the cap ($CAP), not the helper default" "$(echo "$out" | sed -n 's/^fixture-cap=//p' | head -1)" "$CAP"
echo "$out" | sed 's/^/  trap-handler: /'
polls=$(echo "$out" | sed -n 's/.*polls=\([0-9]*\).*/\1/p' | head -1)
check "TERM-obeying job stopped from inside a trap handler ends the wait promptly (polls $polls, cap $CAP)" "$([ -n "$polls" ] && [ "$polls" -le 3 ] && echo prompt || echo "polls=$polls")" prompt
check "no KILL for a job that obeys TERM" "$(echo "$out" | grep -c 'killed=1')" 0

# ── N1b: the REAL finalize shape, as a FILE with the cap named and asserted ──
# The driver spawns its job(s), records $! in pids[], blocks in `wait`, an EXTERNAL
# TERM arrives, and the TRAP handler calls stop_running_jobs. The last-started job
# (the `$!` one) stays RETAINED in bash's table after it exits; `kill -0 %N` and
# `jobs -rp %N` (explicit spec ignores -r) both keep reporting it present, so with
# either the poll burned the whole cap and then sent a no-op KILL (polls=cap
# killed=1). Promptness is asserted by poll COUNT and killed=0, never by time.
WS=$(mktemp "${TMPDIR:-/tmp}/stop-running-jobs-ws.XXXXXX")
cat > "$WS" <<'WAITSHAPE'
source "$1"
SCEN_CAP=$2          # named BEFORE the trap: a trap calls fin() with no args
MODE=$3; PIDFILE=$4
pids=()
case $MODE in
  wait-exit0)      ( trap 'exit 0' TERM; while :; do sleep 0.2; done ) & pids+=("$!") ;;
  wait-exit1)      ( trap 'exit 1' TERM; while :; do sleep 0.2; done ) & pids+=("$!") ;;
  wait-selffinish) ( trap '' TERM; sleep 2; exit 0 ) & pids+=("$!") ;;
  sleeploop-exit0) ( trap 'exit 0' TERM; while :; do sleep 0.2; done ) & ;;
  ignoring)        ( trap '' TERM; while :; do sleep 0.2; done ) & pids+=("$!") ;;
  ten)             for k in 1 2 3 4 5 6 7 8 9 10; do ( trap 'exit 0' TERM; while :; do sleep 0.2; done ) & pids+=("$!"); done ;;
esac
echo "fixture-cap=$SCEN_CAP"
fin() { trap - EXIT INT TERM HUP; stop_running_jobs "$SCEN_CAP"; exit 0; }
trap fin EXIT; trap 'exit 143' TERM
echo $$ > "$PIDFILE"
if [ "${#pids[@]}" -gt 0 ]; then
    while [ "${#pids[@]}" -gt 0 ]; do wait "${pids[0]}" || true; pids=("${pids[@]:1}"); done
else
    while :; do sleep 0.1; done
fi
WAITSHAPE
ws_run() { # mode -> output of the scenario after an external TERM
    local mode=$1 pf; pf=$(mktemp "${TMPDIR:-/tmp}/stop-running-jobs-ws.pid.XXXXXX")
    bash "$WS" "$ROOT/test/install-recovery/lxd/proc-tree.sh" "$CAP" "$mode" "$pf" > "$pf.out" 2>&1 &
    local b=$! w=0
    while [ ! -s "$pf" ] && [ "$w" -lt 100 ]; do sleep 0.1; w=$((w+1)); done
    sleep 1
    /bin/kill -TERM "$(cat "$pf")" 2>/dev/null
    wait "$b" 2>/dev/null
    cat "$pf.out"; rm -f "$pf" "$pf.out"
}
for mode in wait-exit0 wait-exit1 wait-selffinish sleeploop-exit0; do
    out=$(ws_run "$mode")
    echo "$out" | sed "s/^/  $mode: /"
    check "$mode: the fixture really passes the cap ($CAP)" "$(echo "$out" | sed -n 's/^fixture-cap=//p' | head -1)" "$CAP"
    polls=$(echo "$out" | sed -n 's/.*polls=\([0-9]*\).*/\1/p' | head -1)
    check "$mode: retained finished job ends the wait promptly (polls ${polls:-none}, cap $CAP)" "$([ -n "$polls" ] && [ "$polls" -le 3 ] && echo prompt || echo "polls=${polls:-none}")" prompt
    check "$mode: no KILL for a job that finished by itself" "$(echo "$out" | grep -c 'killed=1')" 0
done
out=$(ws_run ignoring)
echo "$out" | sed 's/^/  ignoring: /'
check "a job that ignores TERM and never finishes is still KILLed after the full cap" "$(echo "$out" | grep -c "polls=$CAP killed=1")" 1

# exact job number: with ten jobs the table holds %1 and %10; %1 must never be
# matched for %10 (a prefix match would leave %1 "running" once it is retained).
out=$(ws_run ten)
check "ten jobs: every job stopped, none KILLed, none burned the cap" "$(echo "$out" | grep -c 'killed=0')" 10
check "ten jobs: %10 is reported as its own job" "$([ "$(echo "$out" | grep -c 'stop_running_jobs: %10 ')" = 1 ] && echo y)" y
rm -f "$WS"

# ── strict no-selection: a job that COMPLETED BEFORE selection must not be selected ──
# The LAST-started job ($! kept in pids[], reference retained) has already
# finished, completion observed via a marker file, and stays listed ("Exit 3").
# The main shell sits in a sleep loop (no `wait` or timer that would drop it), so it
# is still in bash's table when the TERM handler selects. `jobs -r` must not list
# it, so nothing is selected; selecting from plain `jobs` would pick %1.
DB=$(mktemp "${TMPDIR:-/tmp}/stop-running-jobs-db.XXXXXX")
cat > "$DB" <<'DONEBEFORE'
source "$1"
SCEN_CAP=$2; PIDFILE=$3; DONE=$4
pids=()
( : > "$DONE"; exit 3 ) & pids+=("$!")
fin() { trap - EXIT INT TERM HUP; echo "listed-at-selection=$(jobs | grep -c 'Exit 3')"; stop_running_jobs "$SCEN_CAP"; echo "end-of-stop"; exit 0; }
trap fin EXIT; trap 'exit 143' TERM
echo $$ > "$PIDFILE"
while :; do sleep 0.1; done
DONEBEFORE
dbpf=$(mktemp "${TMPDIR:-/tmp}/stop-running-jobs-db.pid.XXXXXX"); dbdone="$dbpf.done"
bash "$DB" "$ROOT/test/install-recovery/lxd/proc-tree.sh" "$CAP" "$dbpf" "$dbdone" > "$dbpf.out" 2>&1 &
dbb=$!; w=0
while { [ ! -s "$dbpf" ] || [ ! -e "$dbdone" ]; } && [ "$w" -lt 100 ]; do sleep 0.1; w=$((w+1)); done
sleep 1
/bin/kill -TERM "$(cat "$dbpf")" 2>/dev/null
wait "$dbb" 2>/dev/null
out=$(cat "$dbpf.out")
echo "$out" | sed 's/^/  completed-before: /'
check "completed-before: the finished job was still LISTED at selection (precondition)" "$(echo "$out" | sed -n 's/^listed-at-selection=//p')" 1
check "completed-before: a job already finished at selection is not selected or signalled" "$(echo "$out" | grep -c '^stop_running_jobs:')" 0
check "completed-before: the stop completed" "$(echo "$out" | grep -c '^end-of-stop')" 1

# ── exact job number: a retained finished %1 beside a RUNNING %10 ─────────────
# _job_running %1 must be false and %10 true; a prefix match (^\[1) wrongly calls %1 running.
EN=$(mktemp "${TMPDIR:-/tmp}/stop-running-jobs-num.XXXXXX")
cat > "$EN" <<'NUMSCEN'
source "$1"
( exit 0 ) &
sleep 0.4
for k in 2 3 4 5 6 7 8 9; do ( sleep 0.05 ) & done
( trap '' TERM; while :; do sleep 0.2; done ) & live10=$!
sleep 0.3
echo "job1-running=$(_job_running %1 && echo yes || echo no)"
echo "job10-running=$(_job_running %10 && echo yes || echo no)"
/bin/kill -KILL "$live10" 2>/dev/null
exit 0
NUMSCEN
out=$(bash "$EN" "$ROOT/test/install-recovery/lxd/proc-tree.sh" 2>&1)
check "exact number: finished-and-retained %1 is not running" "$(echo "$out" | sed -n 's/^job1-running=//p')" no
check "exact number: running %10 is running" "$(echo "$out" | sed -n 's/^job10-running=//p')" yes
rm -f "$EN" "$DB"

out=$(run_case already 2>&1)
echo "$out" | sed 's/^/  already: /'
check "an already-finished job is not selected" "$(echo "$out" | grep -c 'stop_running_jobs:')" 0

[ "$fails" -eq 0 ] && echo "PASS: stop_running_jobs is prompt on finished jobs and still KILLs a TERM-ignoring one" || exit 1
