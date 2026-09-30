#!/usr/bin/env bash
# STATBUS-425 M3b: executes the REAL run-arcs.sh (copied byte-for-byte into a
# throwaway git repo) with the host-side collaborators stubbed (lxd backend,
# marker, construct, branch deletion, arcs). Proves, on the real finalize:
#   A. an exit before construct keeps its exit code (no unbound RUN_ID) and
#      restores the pinned tree only while the construct lock is held,
#      releasing the lock after the restore;
#   B. a real SIGTERM during the arcs phase (lock already released) leaves NO
#      owned process alive (arc, its TERM-ignoring orphan) before the marker
#      release and fixture-branch deletion, never checks out the shared
#      pinned tree, and exits 143;
#   C. a construct failure restores the tree under the lock, before release.
set -uo pipefail
SRC=$(cd "$(dirname "$0")/../../.." && pwd)
WORK=$(mktemp -d)
watchdog_pid=""
cleanup() {
    [ -z "$watchdog_pid" ] || kill "$watchdog_pid" 2>/dev/null
    if [ -f "$WORK/owned.pids" ]; then while read -r p; do kill -KILL "$p" 2>/dev/null; done < "$WORK/owned.pids"; fi
    rm -rf "$WORK"
}
trap cleanup EXIT
# Outer bounded watchdog for the whole test.
( sleep 420; echo "FAIL: test watchdog fired" >&2; kill -TERM $$ ) >/dev/null 2>&1 </dev/null & watchdog_pid=$!
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }

R="$WORK/repo"
mkdir -p "$R/test/install-recovery/lxd" "$R/test/install-recovery/lib" "$R/test/install-recovery/arcs" "$R/ops/lxd-fleet"
cp "$SRC/test/install-recovery/lxd/run-arcs.sh" "$SRC/test/install-recovery/lxd/proc-tree.sh" "$SRC/test/install-recovery/lxd/arc-job.sh" "$R/test/install-recovery/lxd/"
# Slot admission is tested by lxd-admission-test.sh; here it is a no-op stub.
cat > "$R/ops/lxd-fleet/admission.sh" <<'EOS'
lxd_marker_id() { printf '%s.manual-%s-%s' "${1//[^a-zA-Z0-9-]/-}" "$2" "$$"; }
# STUB_ACQUIRE_BLOCK=1: acquire waits (like the real bounded poll) until the
# test drops allow-acquire, then records slot-acquired.
lxd_slot_acquire() {
    if [ "${STUB_ACQUIRE_BLOCK:-0}" = 1 ]; then
        echo "acquire-waiting" >> "$EV"
        while [ ! -f "$WORK/allow-acquire" ]; do sleep 0.3; done
        echo "slot-acquired" >> "$EV"
    fi
    LXD_SLOT=1
}
lxd_slot_release() { echo "slot-release" >> "$EV"; }
EOS
# STUB_TERM_IGNORE=1: the per-arc job shell itself genuinely ignores TERM and
# never returns (a job only SIGKILL can stop). Replaces lxd_arc_run.
cat >> "$R/test/install-recovery/lxd/arc-job.sh" <<'EOS'
if [ "${STUB_TERM_IGNORE:-0}" = 1 ]; then
    lxd_arc_run() {
        trap '' TERM
        sh -c 'echo $PPID' >> "$WORK/owned.pids"   # this job shell's own pid
        touch "$WORK/prompt-started"
        while :; do sleep 1; done
    }
fi
EOS
# STATBUS_RB125: run_bounded reports it could NOT empty the group (rc 125) while
# a real, separate process group is still alive (the recorded pgid).
cat >> "$R/test/install-recovery/lxd/proc-tree.sh" <<'EOS'
if [ "${STUB_RB125:-0}" = 1 ]; then
    run_bounded() {
        ( set -m; sleep 250 >/dev/null 2>&1 </dev/null & echo "$!" > "$RUN_BOUNDED_PGID_FILE"; echo "$!" >> "$WORK/owned.pids" )
        echo stub-arc-output > "$3"
        return 125
    }
fi
EOS
EV="$WORK/events"; : > "$EV"
cat > "$R/test/install-recovery/lib/lxd-backend.sh" <<'EOS'
LXD_HOST=stubhost; _LXD_REAL_SSH=/usr/bin/ssh
lxd_base_for_candidate() { :; }
EOS
cat > "$R/ops/lxd-fleet/marker.sh" <<'EOS'
lxd_marker_acquire() { echo "marker-acquire" >> "$EV"; }
lxd_marker_release() {
    local alive=0 p
    if [ -f "$WORK/owned.pids" ]; then while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive+1)); done < "$WORK/owned.pids"; fi
    echo "marker-release owned_alive=$alive" >> "$EV"
}
EOS
cat > "$R/test/install-recovery/lib/upgrade-target.sh" <<'EOS'
construct_upgrade_target() {
    [ "${STUB_CONSTRUCT_FAIL:-0}" = 1 ] && { echo "stub construct failure" >&2; return 1; }
    B_FULL="" B_BRANCH="" C_FULL="" C_BRANCH="" V_VERSION="" V_VERSION_2="" V_VERSION_3="" B_SHORT=""
}
delete_throwaway_branches() {
    local alive=0 p
    if [ -f "$WORK/owned.pids" ]; then while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive+1)); done < "$WORK/owned.pids"; fi
    echo "branch-delete owned_alive=$alive" >> "$EV"
}
EOS
cat > "$R/test/install-recovery/arcs/stubarc-arc.sh" <<'EOS'
#!/usr/bin/env bash
# The arc shell exits on TERM, leaving a TERM-ignoring reparented orphan.
( trap '' TERM; exec sleep 250 ) & orphan=$!
echo "$$" >> "$WORK/owned.pids"; echo "$orphan" >> "$WORK/owned.pids"
touch "$WORK/arc-started"
trap 'exit 1' TERM
while :; do sleep 1; done
EOS
# A second arc that exits at once: by the time finalize runs its job is
# finished and already reaped (bash 3.2 still lists it under `jobs -p`). It
# must be selected AFTER the long arc: the driver `wait`s on the first arc
# first, and only an un-waited finished job stays in the table.
cat > "$R/test/install-recovery/arcs/instantarc-arc.sh" <<'EOS'
#!/usr/bin/env bash
touch "$WORK/instant-done"
exit 0
EOS
git -C "$R" init -q
git -C "$R" config core.hooksPath "$R/.git/hooks"
git -C "$R" add -A
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -C "$R" -c commit.gpgsign=false commit -q -m base
TAGN=v1.2.3-rc.4
git -C "$R" -c tag.gpgsign=false tag "$TAGN"
mkdir -p "$R/.git/hooks"
cat > "$R/.git/hooks/post-checkout" <<'EOS'
#!/bin/sh
if [ -d "$LOCKDIR" ]; then echo "checkout lock=held" >> "$EV"; else echo "checkout lock=free" >> "$EV"; fi
EOS
chmod +x "$R/.git/hooks/post-checkout"

export WORK EV JCODE_SCRATCH_DIR="$WORK/scratch"; mkdir -p "$JCODE_SCRATCH_DIR"
LOCKDIR="$JCODE_SCRATCH_DIR/lxd-s2-pinned-${TAGN//[^a-zA-Z0-9-]/-}.construct.lock.d"; export LOCKDIR
DRV="$R/test/install-recovery/lxd/run-arcs.sh"
# Pre-create the pinned worktree so its creation checkout (which fires the
# hook before any lock exists) is not counted as a driver checkout.
git -C "$R" worktree add -q --detach "$JCODE_SCRATCH_DIR/lxd-s2-pinned-${TAGN//[^a-zA-Z0-9-]/-}" "$TAGN"
export ARC_NO_PUSH=0 ARC_TIMEOUT_GRACE_S=3 DIRLOCK_POLL_S=1

# ── A: exit before construct (unknown arc) ────────────────────────────────
: > "$EV"
out=$(bash "$DRV" "$TAGN" --arc nonesuch 2>&1); rc=$?
check "A: exit code preserved (2), not turned into 1" "$rc" 2
case "$out" in *"unbound variable"*) echo "FAIL A: unbound variable: $out"; fails=$((fails+1));; *) echo "ok   A: no unbound variable";; esac
check "A: restore ran only under lock" "$(grep -c 'checkout lock=free' "$EV")" 0
check "A: restore ran once under lock" "$(grep -c 'checkout lock=held' "$EV")" 1
check "A: lock released after restore" "$([ -d "$LOCKDIR" ] && echo held || echo free)" free
check "A: no branch deletion (RUN_ID unset)" "$(grep -c branch-delete "$EV")" 0

# ── C: construct failure restores under lock, before release ─────────────
: > "$EV"
STUB_CONSTRUCT_FAIL=1 bash "$DRV" "$TAGN" --arc stubarc >/dev/null 2>&1; rc=$?
check "C: construct failure rc" "$([ "$rc" -ne 0 ] && echo nonzero)" nonzero
check "C: restore ran under lock" "$(grep -c 'checkout lock=held' "$EV")" 1
check "C: no restore outside lock" "$(grep -c 'checkout lock=free' "$EV")" 0
check "C: lock released after" "$([ -d "$LOCKDIR" ] && echo held || echo free)" free

# ── B: SIGTERM during the arcs phase ─────────────────────────────────────
# `kill` observer, inherited by the real driver (and by nothing else: the test
# process itself is skipped via TEST_PID). It resolves the target the way the
# driver addressed it:
#   - a jobspec (%N): resolved through bash's OWN current job table in the
#     driver's shell (`jobs -p %N`). A spec bash refuses ("no such job") means
#     no signal can be sent: counted as NOT signalled, which is the invariant.
#   - a raw pid: if it is no longer alive it is an already-reaped, possibly
#     reused pid, so a TERM/KILL aimed at it is a violation (signal-dead-pid).
# Optional deterministic race hook (RACE_HOOK=1): before the FIRST signal to a
# still-running job, that job is made to exit and be reaped, reproducing the
# window between finalize's job snapshot and its signal.
export TEST_PID=$$
kill() {
    if [ "$$" != "$TEST_PID" ]; then
        case "${1:-}:${2:-}" in
            -TERM:*|-KILL:*)
                local tgt=$2 pid=
                case "$tgt" in
                    %*) pid=$(jobs -p "$tgt" 2>/dev/null | head -n1) ;;
                    [0-9]*) pid=$tgt ;;
                esac
                if [ "${RACE_HOOK:-0}" = 1 ] && [ ! -e "$WORK/race-fired" ] && [ -n "$pid" ] && builtin kill -0 "$pid" 2>/dev/null; then
                    : > "$WORK/race-fired"
                    echo "hook: job $pid exits between finalize's snapshot and its signal (target $tgt)" >> "$EV"
                    builtin kill -KILL "$pid" 2>/dev/null
                    for _i in 1 2 3 4 5 6 7 8 9 10; do builtin kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
                    # bash 3.2 reaps the exited child; give its SIGCHLD handling a moment
                    sleep 0.3
                fi
                case "$tgt" in
                    %*) if [ -z "$(jobs -p "$tgt" 2>/dev/null)" ]; then echo "jobspec-refused $tgt" >> "$EV"; else echo "signal-live-job $tgt" >> "$EV"; echo "sent $1 $tgt" >> "$EV"; fi ;;
                    [0-9]*) builtin kill -0 "$tgt" 2>/dev/null || echo "signal-dead-pid $tgt" >> "$EV" ;;
                esac ;;
        esac
    fi
    builtin kill "$@"
}
export -f kill
: > "$EV"; rm -f "$WORK/owned.pids" "$WORK/arc-started" "$WORK/instant-done" "$WORK/race-fired"
RACE_HOOK=0; export RACE_HOOK
bash "$DRV" "$TAGN" --arc stubarc --arc instantarc >"$WORK/b.out" 2>&1 &
drv=$!
w=0; while { [ ! -f "$WORK/arc-started" ] || [ ! -f "$WORK/instant-done" ]; } && [ "$w" -lt 60 ]; do sleep 1; w=$((w+1)); done
check "B: both arcs started" "$([ -f "$WORK/arc-started" ] && [ -f "$WORK/instant-done" ] && echo y)" y
sleep 2
pre_checkouts=$(grep -c '^checkout' "$EV")
check "B: lock already released in arcs phase" "$([ -d "$LOCKDIR" ] && echo held || echo free)" free
kill -TERM "$drv"
w=0; while kill -0 "$drv" 2>/dev/null && [ "$w" -lt 90 ]; do sleep 1; w=$((w+1)); done
if kill -0 "$drv" 2>/dev/null; then echo "FAIL B: driver did not exit"; kill -KILL "$drv"; fails=$((fails+1)); fi
wait "$drv" 2>/dev/null; rc=$?
check "B: exit 143" "$rc" 143
check "B: no checkout of the shared tree after lock release" "$(grep -c '^checkout' "$EV")" "$pre_checkouts"
alive=0; while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive+1)); done < "$WORK/owned.pids"
check "B: no owned process survives (arc + orphan)" "$alive" 0
check "B: marker released with 0 owned alive" "$(grep -c 'marker-release owned_alive=0' "$EV")" 1
check "B: branches deleted with 0 owned alive" "$(grep -c 'branch-delete owned_alive=0' "$EV")" 7
check "B: finalize never signalled an already-reaped pid" "$(grep -c '^signal-dead-pid' "$EV")" 0

# ── B2: deterministic regression for the snapshot-to-signal window ───────────
# A job exits and is reaped AFTER finalize selected it and BEFORE the signal lands.
# With raw pids this sent a signal to a dead (reusable) pid; jobspecs are refused by
# bash itself, so nothing is signalled. Everything else B checks must still hold.
: > "$EV"; rm -f "$WORK/owned.pids" "$WORK/arc-started" "$WORK/instant-done" "$WORK/race-fired"
RACE_HOOK=1; export RACE_HOOK
bash "$DRV" "$TAGN" --arc stubarc --arc instantarc >"$WORK/b.out" 2>&1 &
drv=$!
w=0; while { [ ! -f "$WORK/arc-started" ] || [ ! -f "$WORK/instant-done" ]; } && [ "$w" -lt 60 ]; do sleep 1; w=$((w+1)); done
check "B2: both arcs started" "$([ -f "$WORK/arc-started" ] && [ -f "$WORK/instant-done" ] && echo y)" y
sleep 2
pre_checkouts=$(grep -c '^checkout' "$EV")
check "B2: lock already released in arcs phase" "$([ -d "$LOCKDIR" ] && echo held || echo free)" free
kill -TERM "$drv"
w=0; while kill -0 "$drv" 2>/dev/null && [ "$w" -lt 90 ]; do sleep 1; w=$((w+1)); done
if kill -0 "$drv" 2>/dev/null; then echo "FAIL B2: driver did not exit"; kill -KILL "$drv"; fails=$((fails+1)); fi
wait "$drv" 2>/dev/null; rc=$?
check "B2: exit 143" "$rc" 143
check "B2: no checkout of the shared tree after lock release" "$(grep -c '^checkout' "$EV")" "$pre_checkouts"
alive=0; while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive+1)); done < "$WORK/owned.pids"
check "B2: no owned process survives (arc + orphan)" "$alive" 0
check "B2: marker released with 0 owned alive" "$(grep -c 'marker-release owned_alive=0' "$EV")" 1
check "B2: branches deleted with 0 owned alive" "$(grep -c 'branch-delete owned_alive=0' "$EV")" 7
check "B2: finalize never signalled an already-reaped pid" "$(grep -c '^signal-dead-pid' "$EV")" 0
check "B2: the race hook actually fired (a job exited between snapshot and signal)" "$([ -e "$WORK/race-fired" ] && echo y)" y
RACE_HOOK=0; export RACE_HOOK
check "B: no release/delete saw a live child" "$(grep -c 'owned_alive=[1-9]' "$EV")" 0

# ── D: run_bounded returns 125 (owned group NOT emptied) ─────────────────
# Real driver + real arc-job.sh. The 125 must survive to the caller, the slot
# must stay held while the group lives, the pgid file must stay reachable so
# finalize can stop it, and marker/branch cleanup may only happen after.
: > "$EV"; rm -f "$WORK/owned.pids"
STUB_RB125=1 bash "$DRV" "$TAGN" --arc stubarc >"$WORK/d.out" 2>&1; rc=$?
tsv=$(ls -d "$JCODE_SCRATCH_DIR"/lxd-s2-pinned-*/tmp/lxd-arcs-* | tail -1)/comparison.tsv
check "D: no slot released while group alive" "$(grep -c '^slot-release' "$EV")" 0
check "D: real rc 125 recorded, not collapsed to 1" "$(awk -F'\t' '$1=="stubarc"{print $5}' "$tsv")" 125
check "D: driver fails" "$([ "$rc" -ne 0 ] && echo nonzero)" nonzero
alive=0; while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive+1)); done < "$WORK/owned.pids"
check "D: finalize (blind before fix) stopped the retained group" "$alive" 0
check "D: marker released only with 0 owned alive" "$(grep -c 'marker-release owned_alive=0' "$EV")" 1
check "D: nothing released/deleted while owned alive" "$(grep -c 'owned_alive=[1-9]' "$EV")" 0

# ── E: a job that FINISHES during finalize's wait must not burn the grace ───
# `kill -0 %N` answers "alive" for a job that already finished but is still
# listed (bash serves it from the job table, no syscall), so finalize spun for
# the whole ARC_TIMEOUT_GRACE_S+40 on every such job. The running-job table
# (`jobs -rp %N`) is the predicate instead. The grace is 100 s (cap 140 s) and
# the deadline a roomy 60 s: a loaded host cannot flake it, the regression
# (>= 140 s) is unmistakable. The arc finishes on its own after finalize has
# selected and TERMed its job (the test drops a release file at that point).
# The per-arc job runs lxd_arc_run directly in the job shell (no $(...)), so its
# run_bounded TERM trap handles finalize's TERM promptly. E2 separately covers a
# job that genuinely ignores TERM.
cat > "$R/test/install-recovery/arcs/promptarc-arc.sh" <<'EOS'
#!/usr/bin/env bash
echo "$$" >> "$WORK/owned.pids"
touch "$WORK/prompt-started"
while [ ! -f "$WORK/release" ]; do sleep 0.5; done
echo "PASS: released"
EOS
: > "$EV"; rm -f "$WORK/owned.pids" "$WORK/prompt-started" "$WORK/release"
ARC_TIMEOUT_GRACE_S=100 bash "$DRV" "$TAGN" --arc promptarc >"$WORK/e.out" 2>&1 &
drv=$!
w=0; while [ ! -f "$WORK/prompt-started" ] && [ "$w" -lt 60 ]; do sleep 1; w=$((w+1)); done
check "E: arc started" "$([ -f "$WORK/prompt-started" ] && echo y)" y
sleep 2
t0=$(date +%s)
kill -TERM "$drv"
w=0; while ! grep -q '^sent -TERM %' "$EV" && [ "$w" -lt 60 ]; do sleep 0.5; w=$((w+1)); done
check "E: finalize selected and TERMed the running job first" "$([ "$(grep -c '^sent -TERM %' "$EV")" -ge 1 ] && echo y)" y
: > "$WORK/release"        # the arc now finishes on its own, DURING finalize's wait
w=0; while kill -0 "$drv" 2>/dev/null && [ "$w" -lt 170 ]; do sleep 1; w=$((w+1)); done
if kill -0 "$drv" 2>/dev/null; then echo "FAIL E: driver did not exit"; kill -KILL "$drv"; fails=$((fails+1)); fi
wait "$drv" 2>/dev/null; rc=$?
took=$(( $(date +%s) - t0 ))
check "E: exit 143" "$rc" 143
check "E: a job that finished during the wait did not burn the grace (took ${took}s, cap 140s, deadline 60s)" "$([ "$took" -lt 60 ] && echo prompt || echo "slow:${took}s")" prompt
check "E: no KILL for a job that finished by itself" "$(grep -c '^sent -KILL' "$EV")" 0
alive=0; while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive+1)); done < "$WORK/owned.pids"
check "E: no owned process survives" "$alive" 0
check "E: finalize never signalled an already-reaped pid" "$(grep -c '^signal-dead-pid' "$EV")" 0

# ── E2: a job that genuinely IGNORES TERM is still forcibly stopped ─────────
# The job shell itself runs `trap '' TERM` and never returns (STUB_TERM_IGNORE
# replaces lxd_arc_run). After the (short) grace cap finalize must send KILL
# THROUGH THE JOBSPEC (never a raw pid) and leave nothing alive.
: > "$EV"; rm -f "$WORK/owned.pids" "$WORK/prompt-started" "$WORK/release"
STUB_TERM_IGNORE=1 ARC_TIMEOUT_GRACE_S=3 bash "$DRV" "$TAGN" --arc promptarc >"$WORK/e2.out" 2>&1 &
drv=$!
w=0; while [ ! -f "$WORK/prompt-started" ] && [ "$w" -lt 60 ]; do sleep 1; w=$((w+1)); done
check "E2: arc started" "$([ -f "$WORK/prompt-started" ] && echo y)" y
sleep 2
kill -TERM "$drv"
w=0; while kill -0 "$drv" 2>/dev/null && [ "$w" -lt 120 ]; do sleep 1; w=$((w+1)); done
if kill -0 "$drv" 2>/dev/null; then echo "FAIL E2: driver did not exit"; kill -KILL "$drv"; fails=$((fails+1)); fi
wait "$drv" 2>/dev/null; rc=$?
check "E2: exit 143" "$rc" 143
check "E2: TERM went to the job's jobspec" "$([ "$(grep -c '^sent -TERM %' "$EV")" -ge 1 ] && echo y)" y
check "E2: a job that never finished was forcibly KILLed via its jobspec" "$([ "$(grep -c '^sent -KILL %' "$EV")" -ge 1 ] && echo y)" y
alive=0; while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive+1)); done < "$WORK/owned.pids"
check "E2: no owned process survives" "$alive" 0
check "E2: finalize never signalled an already-reaped pid" "$(grep -c '^signal-dead-pid' "$EV")" 0

# ── F: job LEADER killed while it waits for admission ───────────────────────
# Ownership invariant: nothing the driver owns may touch admission (acquire /
# release) or start an arc AFTER the driver released its marker. The job leader
# is the process that owns the slot and runs run_bounded, so killing it must
# leave no orphan that later claims a slot. The race hook KILLs the leader at
# finalize's first signal while the acquire stub is still waiting.
: > "$EV"; rm -f "$WORK/owned.pids" "$WORK/allow-acquire" "$WORK/race-fired" "$WORK/arc-started"
RACE_HOOK=1; export RACE_HOOK
STUB_ACQUIRE_BLOCK=1 ARC_TIMEOUT_GRACE_S=3 bash "$DRV" "$TAGN" --arc stubarc >"$WORK/f.out" 2>&1 &
drv=$!
w=0; while ! grep -q '^acquire-waiting' "$EV" && [ "$w" -lt 60 ]; do sleep 1; w=$((w+1)); done
check "F: job is waiting for admission" "$([ "$(grep -c '^acquire-waiting' "$EV")" -ge 1 ] && echo y)" y
kill -TERM "$drv"
w=0; while kill -0 "$drv" 2>/dev/null && [ "$w" -lt 120 ]; do sleep 1; w=$((w+1)); done
if kill -0 "$drv" 2>/dev/null; then echo "FAIL F: driver did not exit"; kill -KILL "$drv"; fails=$((fails+1)); fi
wait "$drv" 2>/dev/null; rc=$?
RACE_HOOK=0; export RACE_HOOK
check "F: exit 143" "$rc" 143
check "F: the leader kill hook fired" "$([ -e "$WORK/race-fired" ] && echo y)" y
check "F: marker released" "$(grep -c '^marker-release' "$EV")" 1
# Let any surviving waiter proceed, then see whether it touches admission.
: > "$WORK/allow-acquire"
sleep 4
late=$(awk '/^marker-release/{m=1; next} m && /^(slot-acquired|slot-release)/{n++} END{print n+0}' "$EV")
check "F: no slot acquire/release after the marker was released" "$late" 0
check "F: no arc started after the marker was released" "$([ -f "$WORK/arc-started" ] && echo started || echo none)" none
alive=0; if [ -f "$WORK/owned.pids" ]; then while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive+1)); done < "$WORK/owned.pids"; fi
check "F: no owned process survives" "$alive" 0

unset -f kill
[ "$fails" -eq 0 ] && echo "PASS: real run-arcs.sh finalize, signals and early exits" || { sed 's/^/  b.out: /' "$WORK/b.out" 2>/dev/null | tail -20; exit 1; }
