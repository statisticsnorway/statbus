#!/usr/bin/env bash
# Process-group and directory-lock helpers for the LXD drivers (STATBUS-425
# M3b review recommendations 1, 2, 4). Portable to macOS bash 3.2 and Linux
# (no flock, no `timeout`, no `wait -n`, no setsid). Sourced, never executed.
#
# Ownership strategy: process GROUPS, not descendant walks. `set -m` makes a
# background job its own process-group leader (pgid == its pid) on both bash
# 3.2/macOS and Linux. A group survives its leader's exit and keeps every
# member that stays in it, reparented or not, so `kill -- -PGID` still reaches
# a TERM-ignoring orphan after the root has died. A member that deliberately
# leaves the group (setsid, its own `set -m`) is out of scope; the arc
# scripts do neither.

# group_alive PGID — true while any process still exists in group PGID.
group_alive() { kill -0 -- "-$1" 2>/dev/null; }

# stop_group PGID GRACE_S — TERM the group, wait up to GRACE_S for it to
# empty, KILL whatever is left, then wait up to 10s for the kernel to
# finish. Returns 0 only when the group is verifiably empty, 1 otherwise
# (callers must then NOT release resources the group might still use).
stop_group() {
    local pgid="$1" grace="${2:-20}" waited=0
    [[ "$pgid" =~ ^[0-9]+$ ]] || return 0
    group_alive "$pgid" || return 0
    kill -TERM -- "-$pgid" 2>/dev/null || true
    while group_alive "$pgid" && [ "$waited" -lt "$grace" ]; do
        sleep 1; waited=$((waited + 1))
    done
    if group_alive "$pgid"; then
        kill -KILL -- "-$pgid" 2>/dev/null || true
        waited=0
        while group_alive "$pgid" && [ "$waited" -lt 10 ]; do
            sleep 1; waited=$((waited + 1))
        done
    fi
    ! group_alive "$pgid"
}

# run_bounded TIMEOUT_S GRACE_S LOGFILE CMD... — run CMD in its OWN process
# group (stdout+stderr to LOGFILE) and return its rc. The whole group is
# stopped (TERM, GRACE_S, KILL) on:
#   - timeout            -> return 124
#   - TERM/INT/HUP to us -> return 143/130/129 (the caller's trap defers to
#                           the poll loop, which runs at least once a second)
#   - CMD's normal exit  -> return its rc, but leftover group members (a
#                           TERM-ignoring background child) are still stopped
# If RUN_BOUNDED_PGID_FILE is set the group id is written there immediately,
# so an outside supervisor can reach the group if this function is killed.
# Returns 125 if the group could not be emptied.
run_bounded() {
    local timeout="$1" grace="$2" log="$3" apid rc=0 sig=0 timed=0 started had_m=0
    shift 3
    case $- in *m*) had_m=1 ;; esac
    set -m
    "$@" >"$log" 2>&1 &
    apid=$!
    [ "$had_m" = 1 ] || set +m
    [ -z "${RUN_BOUNDED_PGID_FILE:-}" ] || echo "$apid" > "$RUN_BOUNDED_PGID_FILE"
    trap 'sig=143' TERM
    trap 'sig=130' INT
    trap 'sig=129' HUP
    started=$(date +%s)
    while kill -0 "$apid" 2>/dev/null; do
        [ "$sig" -eq 0 ] || break
        if [ "$(( $(date +%s) - started ))" -ge "$timeout" ]; then timed=1; break; fi
        sleep 1
    done
    if [ "$sig" -ne 0 ] || [ "$timed" -eq 1 ]; then
        stop_group "$apid" "$grace" || rc=125
        wait "$apid" 2>/dev/null || true
        if [ "$rc" -ne 125 ]; then
            if [ "$timed" -eq 1 ]; then rc=124; else rc=$sig; fi
        fi
    else
        wait "$apid" 2>/dev/null || rc=$?
        stop_group "$apid" "$grace" || rc=125
    fi
    trap - TERM INT HUP
    return "$rc"
}

# ── mkdir-based directory lock with stale-holder recovery ───────────────────
# The holder file is "<pid> <label>". A lock is STALE only when its holder
# pid is provably gone (`ps -p`; `kill -0` would also fail with EPERM for a
# live process of another user). A directory with no parsable holder is
# stale only once older than 60s (crash between mkdir and the holder write).
# A live holder is NEVER stolen. Reaping is serialized by a second mkdir
# mutex (DIR.reap.d) that carries its own holder file, so a waiter that died
# mid-reap cannot wedge everyone: a stale mutex is moved aside atomically
# (mv), and dirlock_acquire enforces its budget on EVERY loop iteration.
# Residual risk: pid reuse makes a dead holder look alive (waits, then
# refuses at the budget: the safe direction). A stale-mutex takeover racing a
# fresh mutex can let two reapers overlap; reaping only ever removes a lock
# that re-verifies as stale, so the worst case is a redundant removal.

_dl_holder_pid() { awk 'NR==1{print $1}' "$1/holder" 2>/dev/null; }

# dirlock_is_stale DIR
dirlock_is_stale() {
    local dir="$1" pid
    [ -d "$dir" ] || return 1
    pid=$(_dl_holder_pid "$dir")
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        ps -p "$pid" >/dev/null 2>&1 && return 1
        return 0
    fi
    [ -n "$(find "$dir" -maxdepth 0 -mmin +1 2>/dev/null)" ]
}

# dirlock_reap_stale DIR — 0 if DIR was removed, 1 otherwise.
dirlock_reap_stale() {
    local dir="$1" mutex="$1.reap.d" reaped=1
    if ! mkdir "$mutex" 2>/dev/null; then
        # Someone else is reaping. Only if THAT mutex is stale do we clear it
        # (atomic rename, so exactly one waiter wins); the next loop retries.
        if dirlock_is_stale "$mutex" && mv "$mutex" "$mutex.dead.$$" 2>/dev/null; then
            rm -rf "$mutex.dead.$$"
        fi
        return 1
    fi
    echo "$$ reap" > "$mutex/holder"
    if dirlock_is_stale "$dir"; then
        echo "  reaping stale lock $dir (holder: $(cat "$dir/holder" 2>/dev/null || echo none))" >&2
        rm -rf "$dir" && reaped=0
    fi
    rm -rf "$mutex"
    return "$reaped"
}

# dirlock_acquire DIR BUDGET_S LABEL — 0 acquired, 1 budget exhausted.
dirlock_acquire() {
    local dir="$1" budget="$2" label="$3" start
    start=$(date +%s)
    while true; do
        if mkdir "$dir" 2>/dev/null; then
            echo "$$ $label" > "$dir/holder"
            return 0
        fi
        [ "$(( $(date +%s) - start ))" -lt "$budget" ] || return 1
        if dirlock_is_stale "$dir" && dirlock_reap_stale "$dir"; then continue; fi
        sleep "${DIRLOCK_POLL_S:-2}"
    done
}

# _job_running %N — is job number N still RUNNING in this shell? Exact-number
# membership in the PLAIN `jobs -r` list, whose lines start "[N]" then one of
# "+", "-" or a space, so %1 can never match %10. `jobs -rp %N` is NOT a running
# filter: given an explicit jobspec bash ignores -r and prints the pid of any job
# still in its table, finished-but-retained ones included (measured: a job listed
# "Exit 3" still printed its pid while plain `jobs -r` was empty). `kill -0 %N` is
# no better: for a retained finished job it resolves the spec and succeeds
# (bash's kill then skips the dead processes, so nothing is signalled, but it
# cannot tell a finished job from a running one). Only the plain list is reliable.
_job_running() {
    local n=${1#%}
    jobs -r 2>/dev/null | grep -Eq "^\\[${n}\\][-+ ]"
}
# stop_running_jobs CAP_S — stop every RUNNING background job of the CALLING
# shell (finalize), addressed only by jobspec (%N), never by raw pid:
#   1. select %N from `jobs -r` (already-finished jobs are never selected),
#   2. TERM each, then poll each (_job_running) until it is no longer running or
#      CAP_S passes,
#   3. KILL what is still running, and wait on it.
# Two distinct jobspec behaviours, both measured, matter here:
#   - a job already REMOVED from the table is refused by bash ("no such job") and
#     no signal is sent;
#   - a finished job still RETAINED in the table (listed "Done"/"Exit N") resolves
#     normally; bash's kill then skips its dead processes (source-level liveness
#     check), so nothing is signalled, but every probe that resolves the spec
#     (`kill -0 %N`, `jobs -rp %N`) still reports it present. That is why the
#     liveness predicate is _job_running (plain `jobs -r`), for the wait AND the
#     pre-KILL check. Prints `stop_running_jobs: %N polls=K killed=0|1` per job
#     (K = sleep iterations) so callers and tests can observe promptness without
#     a wall-clock ceiling.
stop_running_jobs() {
    local cap=${1:-160} live spec waited killed
    live=$(jobs -r 2>/dev/null | sed -n 's/^\[\([0-9][0-9]*\)\].*/%\1/p' || true)
    for spec in $live; do
        kill -TERM "$spec" 2>/dev/null || true
    done
    for spec in $live; do
        waited=0 killed=0
        while _job_running "$spec" && [ "$waited" -lt "$cap" ]; do
            sleep 1; waited=$((waited + 1))
        done
        if _job_running "$spec"; then
            kill -KILL "$spec" 2>/dev/null || true
            killed=1
        fi
        wait "$spec" 2>/dev/null || true
        echo "stop_running_jobs: $spec polls=$waited killed=$killed"
    done
}
