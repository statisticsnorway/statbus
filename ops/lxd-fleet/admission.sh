#!/usr/bin/env bash
# STATBUS-425 M4: smallest shared-host admission model for concurrent consumers
# (smoke, fault forks, arc forks) of ONE LXD fleet box. Sourced after marker.sh.
#
#   * lxd_marker_id TAG JOB   candidate-scoped marker id "<safe-tag>.<run>-<job>-<pid>"
#   * lxd_slot_acquire/release  bounded host capacity: at most LXD_HOST_SLOTS
#                              guests (forks) run at once, across ALL jobs
#   * fleet-busy.sh (remote)   "is anything OLDER/foreign still on the box?"
#                              (replaces drain-to-zero in lxd-fleet.yaml)
#   * fleet-sweep.sh (remote)  stale-marker and orphan-fork sweep (reap.sh)
#
# Ownership rule (orphan/stale safe): every slot records the marker id of its
# owner. A slot whose owner marker no longer exists in /root/fleet-active (the
# job released it, or the sweep removed it as stale) is reclaimable by the next
# acquirer. A marker older than LXD_STALE_S is stale (nothing legitimate runs
# that long: arc job 120 min, fault workflow 180 min).
LXD_HOST_SLOTS=${LXD_HOST_SLOTS:-8}
LXD_STALE_S=${LXD_STALE_S:-14400}

lxd_marker_id() {
    local job=$2 safe=${1//[^a-zA-Z0-9-]/-}
    [[ "$job" =~ ^[a-zA-Z0-9-]+$ ]] || { echo "Invalid marker job: $job" >&2; return 2; }
    printf '%s.%s-%s-%s' "$safe" "${GITHUB_RUN_ID:-manual}" "$job" "$$"
}

# lxd_marker_acquire with a bounded retry: two ramps/hardening passes can hold
# the refusal files for a short while when faults and arcs start together.
lxd_marker_acquire_wait() {
    local host=$1 id=$2 budget=${3:-600} waited=0
    while ! lxd_marker_acquire "$host" "$id"; do
        [ "$waited" -lt "$budget" ] || { echo "marker $id not acquired within ${budget}s" >&2; return 1; }
        sleep 5; waited=$((waited + 5))
    done
}

# Remote slot claim. Prints the slot number on success, exit 1 when full.
# Runs under the host flock so check-then-claim is atomic across jobs.
_lxd_slot_claim_script='
set -euo pipefail
max=$1; owner=$2; dir=${FLEET_SLOT_DIR:-/root/fleet-slots}; act=${FLEET_ACTIVE_DIR:-/root/fleet-active}
mkdir -p "$dir"
[ -e "$act/$owner" ] || { echo "REFUSE: owner marker $owner not held" >&2; exit 2; }
n=1
while [ "$n" -le "$max" ]; do
    f="$dir/$n"
    cur=$(cat "$f" 2>/dev/null || true)
    if [ -z "$cur" ] || [ ! -e "$act/$cur" ]; then
        printf "%s" "$owner" > "$f"
        echo "$n"; exit 0
    fi
    n=$((n + 1))
done
exit 1
'
_lxd_slot_release_script='
set -euo pipefail
dir=${FLEET_SLOT_DIR:-/root/fleet-slots}
[ "$(cat "$dir/$1" 2>/dev/null || true)" = "$2" ] && rm -f "$dir/$1" || true
'
# lxd_slot_acquire HOST MARKER_ID [BUDGET_S]  -> sets LXD_SLOT
lxd_slot_acquire() {
    local host=$1 owner=$2 budget=${3:-2700} waited=0 out rc
    [[ "$owner" =~ ^[a-zA-Z0-9._-]+$ ]] || return 2
    while :; do
        rc=0
        out=$(_lxd_marker_ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
            "flock /root/fleet-run.lock bash -c '$_lxd_slot_claim_script' _ '$LXD_HOST_SLOTS' '$owner'") || rc=$?
        if [ "$rc" -eq 0 ] && [[ "$out" =~ ^[0-9]+$ ]]; then LXD_SLOT=$out; export LXD_SLOT; return 0; fi
        [ "$rc" -eq 1 ] || { echo "slot claim failed rc=$rc: $out" >&2; return 1; }
        [ "$waited" -lt "$budget" ] || { echo "no host slot within ${budget}s (LXD_HOST_SLOTS=$LXD_HOST_SLOTS)" >&2; return 1; }
        sleep 15; waited=$((waited + 15))
    done
}
lxd_slot_release() {
    local host=$1 slot=$2 owner=$3
    [[ "$slot" =~ ^[0-9]+$ && "$owner" =~ ^[a-zA-Z0-9._-]+$ ]] || return 0
    _lxd_marker_ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
        "bash -c '$_lxd_slot_release_script' _ '$slot' '$owner'" || true
}

# Release EVERY slot owned by OWNER (the job's marker id), for a caller that
# never learned its slot number (a cleanup step after a killed job).
_lxd_slot_release_owned_script='
set -euo pipefail
dir=${FLEET_SLOT_DIR:-/root/fleet-slots}
for f in "$dir"/*; do
    [ -e "$f" ] || continue
    [ "$(cat "$f" 2>/dev/null || true)" = "$1" ] && rm -f "$f" || true
done
'
lxd_slot_release_owned() {
    local host=$1 owner=$2
    [[ "$owner" =~ ^[a-zA-Z0-9._-]+$ ]] || return 2
    _lxd_marker_ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
        "flock /root/fleet-run.lock bash -c '$_lxd_slot_release_owned_script' _ '$owner'"
}
