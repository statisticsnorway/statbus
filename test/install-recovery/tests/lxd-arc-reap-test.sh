#!/usr/bin/env bash
# Behavioural contract (STATBUS-425 M4 review R4). SYNTHETIC host (tmpdir +
# fake lxc), REAL arc-job.sh / admission.sh / marker.sh / proc-tree.sh.
# A "job" acquires marker + slot and starts an owned process group, then is
# SIGKILLed with NO trap (a cancelled runner). Then the real always-step body
# (lxd_arc_reap_own) runs. Proves: the owned group survives the kill, is
# stopped and verified empty, the fork is deleted, and only THEN is the slot
# reclaimable; if the group cannot be emptied, marker and slot stay held.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d); trap 'kill -KILL -- "-${GRP:-0}" 2>/dev/null || true; rm -rf "$TMP"' EXIT
source "$ROOT/test/install-recovery/tests/fake-lxc.sh"; mk_fake_env "$TMP/env"
export FLEET_ACTIVE_DIR=$TMP/root/fleet-active FLEET_SLOT_DIR=$TMP/root/fleet-slots LXD_HOST_SLOTS=1 LXD_HOST=h
mkdir -p "$FLEET_ACTIVE_DIR"
source "$ROOT/ops/lxd-fleet/marker.sh"; source "$ROOT/ops/lxd-fleet/admission.sh"
source "$ROOT/test/install-recovery/lxd/arc-job.sh"
_lxd_marker_ssh() { shift 5; local c=${1//\/root\//$TMP\/root\/}; bash -c "$c"; }   # host stand-in: /root/ -> tmpdir
flock() { shift 1; "$@"; }; export -f flock
fail() { echo "FAIL: $*" >&2; exit 1; }
STATE=$TMP/arc.state; PGF=$TMP/arc.pgid; MARK=v1.job1-1; FORK=s2-v1-arc-x
mkdir -p "$FAKE_STORE/$FORK"

# The job body, exactly the workflow's order: persist ownership first, acquire,
# start the arc in its own process group (run_bounded's set -m shape), record pgid.
cat > "$TMP/job.sh" <<JOB
set -m
source "$ROOT/ops/lxd-fleet/marker.sh"; source "$ROOT/ops/lxd-fleet/admission.sh"
source "$ROOT/test/install-recovery/lxd/arc-job.sh"
_lxd_marker_ssh() { shift 5; local c=\${1//\\/root\\//$TMP\\/root\\/}; bash -c "\$c"; }
export FLEET_ACTIVE_DIR="$FLEET_ACTIVE_DIR" FLEET_SLOT_DIR="$FLEET_SLOT_DIR" LXD_HOST_SLOTS=1
flock() { shift 1; "\$@"; }; export -f flock
lxd_arc_state_write "$STATE" h "$MARK" "$PGF"
lxd_marker_acquire h "$MARK"; lxd_slot_acquire h "$MARK" 0
sleep 300 >/dev/null 2>&1 </dev/null &
echo "\$!" > "$PGF"
echo started > "$TMP/started"
wait
JOB
bash "$TMP/job.sh" >/dev/null 2>&1 </dev/null &
JOB=$!
w=0; while [ ! -f "$TMP/started" ] && [ "$w" -lt 30 ]; do sleep 1; w=$((w+1)); done
[ -f "$TMP/started" ] || fail "job never started"
GRP=$(cat "$PGF")
kill -KILL "$JOB"; wait "$JOB" 2>/dev/null || true       # trap-less kill
kill -0 -- "-$GRP" 2>/dev/null || fail "precondition: owned group should survive the kill"
[ -e "$FLEET_ACTIVE_DIR/$MARK" ] || fail "precondition: marker should still be held"
touch "$FLEET_ACTIVE_DIR/sibling"
lxd_slot_acquire h sibling 0 2>/dev/null && fail "precondition: sibling must not get the slot while the job's marker is held"
echo 'observed: trap-less kill leaves group alive, marker and slot held, sibling blocked'

# ── the real always-step body ───────────────────────────────────────────────
lxd_arc_reap_own "$STATE" "$FORK" || fail "reap failed on a stoppable group"
kill -0 -- "-$GRP" 2>/dev/null && fail "owned group still alive after reap"
[ ! -d "$FAKE_STORE/$FORK" ] || fail "own fork not deleted"
[ ! -e "$FLEET_ACTIVE_DIR/$MARK" ] || fail "marker not released after a verified-empty group"
[ -z "$(cat "$FLEET_SLOT_DIR"/* 2>/dev/null)" ] || fail "reap left the job's slot claim on the host (relied on marker-gone reclaim)"
lxd_slot_acquire h sibling 0 || fail "slot not reclaimable after successful cleanup"
echo 'PASS: killed trap-less job: group stopped+verified, fork deleted, then marker and slot released and reclaimable'
lxd_slot_release h "$LXD_SLOT" sibling

# ── cleanup cannot establish an empty group: ownership must be KEPT ─────────
MARK=v1.job2-1; touch "$FLEET_ACTIVE_DIR/$MARK"
lxd_arc_state_write "$STATE" h "$MARK" "$PGF"
set -m; sleep 300 >/dev/null 2>&1 </dev/null & G2=$!; set +m; echo "$G2" > "$PGF"
lxd_slot_acquire h "$MARK" 0
stop_group() { return 1; }        # the group refuses to die
rc=0; lxd_arc_reap_own "$STATE" "" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "reap claimed success with an unemptied group"
[ -e "$FLEET_ACTIVE_DIR/$MARK" ] || fail "marker released while owned group alive"
touch "$FLEET_ACTIVE_DIR/sib2"; lxd_slot_acquire h sib2 0 2>/dev/null && fail "slot handed to a sibling while owned group alive"
[ -f "$STATE" ] && [ -s "$PGF" ] || fail "ownership evidence (state/pgid) deleted while group alive"
kill -KILL -- "-$G2" 2>/dev/null || kill -KILL "$G2" 2>/dev/null || true
echo 'PASS: an unemptied group keeps marker, slot and evidence (no blind release)'

# no state file = nothing acquired = clean no-op
rm -f "$STATE"; lxd_arc_reap_own "$STATE" "$FORK" >/dev/null || fail "no-state reap should be a no-op success"
echo 'PASS: reap without ownership state is a harmless no-op'

# ── R6: a COMPLETED group's id must never be signalled by the always-step ────
# Real lxd_arc_run (real run_bounded) with a real arc, then the real reap body.
# stop_group is instrumented: any call after a normal exit means the persisted
# group id (dead, possibly reused by an unrelated process) was targeted.
unset -f stop_group; source "$ROOT/test/install-recovery/lxd/proc-tree.sh"
# fresh host state for this section (earlier sections left deliberate claims)
rm -rf "$FLEET_SLOT_DIR"; rm -f "$FLEET_ACTIVE_DIR"/*
export LXD_HOST_SLOTS=4
export ARC_ROOT=$TMP/repo ARC_TIMEOUT_S=30 ARC_TIMEOUT_GRACE_S=2
mkdir -p "$ARC_ROOT/test/install-recovery/arcs"
printf '#!/usr/bin/env bash\necho "PASS: ok"\n' > "$ARC_ROOT/test/install-recovery/arcs/okarc-arc.sh"
printf '#!/usr/bin/env bash\necho "boom"; exit 7\n' > "$ARC_ROOT/test/install-recovery/arcs/badarc-arc.sh"
_real_stop_group=$(declare -f stop_group)
r6_case() { # slug expected_verdict
    local slug=$1 want=$2 m=v1.r6-$1 v rc=0
    touch "$FLEET_ACTIVE_DIR/$m"
    export RUN_BOUNDED_PGID_FILE=$TMP/$slug.pgid
    lxd_arc_state_write "$TMP/$slug.state" h "$m" "$RUN_BOUNDED_PGID_FILE"
    rm -f "$TMP/stop_calls"
    eval "$_real_stop_group"
    stop_group() { echo "$1" >> "$TMP/stop_calls"; return 0; }
    v=$(lxd_arc_run "$slug" "$TMP/$slug.log" "$m") || rc=$?
    v=${v##*$'\n'}
    rm -f "$TMP/stop_calls"   # run_bounded's own normal-exit cleanup may call stop_group; measure only the reap
    [ "$v" = "$want" ] || fail "$slug: verdict '$v', want $want (rc=$rc)"
    [ ! -e "$RUN_BOUNDED_PGID_FILE" ] || fail "$slug: pgid file survived a normal exit (dead group id would be signalled)"
    lxd_arc_reap_own "$TMP/$slug.state" "" >/dev/null || fail "$slug: reap failed"
    [ ! -s "$TMP/stop_calls" ] || fail "$slug: always-reap signalled completed group id $(cat "$TMP/stop_calls")"
    [ ! -e "$FLEET_ACTIVE_DIR/$m" ] || fail "$slug: marker not released"
    [ -z "$(cat "$FLEET_SLOT_DIR"/* 2>/dev/null)" ] || fail "$slug: slot left claimed"
}
r6_case okarc PASS
echo 'PASS: normal PASS: pgid dropped, always-reap signals nothing, marker+slot released'
r6_case badarc FAIL
echo 'PASS: normal FAIL: pgid dropped, always-reap signals nothing, marker+slot released'

# rc 125 through the REAL helper keeps the id as ownership evidence
m=v1.r6-125; touch "$FLEET_ACTIVE_DIR/$m"; export RUN_BOUNDED_PGID_FILE=$TMP/g125.pgid
lxd_arc_state_write "$TMP/g125.state" h "$m" "$RUN_BOUNDED_PGID_FILE"
run_bounded() { set -m; sleep 300 >/dev/null 2>&1 </dev/null & echo "$!" > "$RUN_BOUNDED_PGID_FILE"; set +m; G125=$!; echo x > "$3"; return 125; }
rc=0; lxd_arc_run okarc "$TMP/g125.log" "$m" >/dev/null || rc=$?
[ "$rc" = 125 ] && [ -s "$RUN_BOUNDED_PGID_FILE" ] || fail "125 through the helper lost the ownership evidence (rc=$rc)"
[ -e "$FLEET_ACTIVE_DIR/$m" ] || fail "125: marker released while group alive"
kill -KILL -- "-$G125" 2>/dev/null || kill -KILL "$G125" 2>/dev/null || true
echo 'PASS: rc 125 through the real helper keeps pgid, marker and slot as ownership evidence'
