#!/usr/bin/env bash
# STATBUS-425 M4: the ONE per-arc execution helper, sourced by run-arcs.sh (all
# arcs of a local/manual run) and run by upgrade-arc-harness.yaml's run-arc job
# (one arc per matrix job, so the per-arc job name stays the gate mark).
# Behaviour lives here once; neither caller re-implements it.
#
#   lxd_arc_run SLUG LOG MARKER_ID   claims a host slot (bounded shared
#     capacity), runs test/install-recovery/arcs/SLUG-arc.sh under
#     run_bounded, releases the slot, prints PASS|FAIL|FAIL_NO_PASS_LINE and
#     returns 0 only for PASS. Caller already holds MARKER_ID.
#
# Names: fork = <prefix>-<safe-tag>-arc-<slug> (backend), VM_NAME =
# statbus-arc-<slug>, log/pgid file per slug: unique per job by construction.
[ -n "${_LXD_ARC_JOB_SH:-}" ] && return 0
_LXD_ARC_JOB_SH=1
_ARC_JOB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$_ARC_JOB_DIR/proc-tree.sh"
source "$_ARC_JOB_DIR/../../../ops/lxd-fleet/admission.sh"

# Pure verdict: rc and log -> PASS|FAIL|FAIL_NO_PASS_LINE (rc=0 without a PASS:
# line means the arc exited early; never a pass).
lxd_arc_verdict() {
    local log=$1 rc=$2
    if [ "$rc" -ne 0 ]; then echo FAIL
    elif ! grep -q '^PASS: ' "$log"; then echo FAIL_NO_PASS_LINE
    else echo PASS; fi
}

lxd_arc_run() {
    local slug=$1 log=$2 marker=$3 rc=0 verdict arc_root
    arc_root=${ARC_ROOT:-$(cd "$_ARC_JOB_DIR/../../.." && pwd)}
    [ -f "$arc_root/test/install-recovery/arcs/${slug}-arc.sh" ] || { echo "Unknown arc: $slug" >&2; return 2; }
    lxd_slot_acquire "$LXD_HOST" "$marker" "${ARC_SLOT_WAIT_S:-2700}" || { echo FAIL; return 1; }
    local slot=$LXD_SLOT
    export LXD_MARKER_ID=$marker   # builder ownership for shared A checkpoints
    local arc_locale=${LC_ALL:-C}
    [ "$(uname -s)" != Darwin ] || arc_locale=C
    LC_ALL="$arc_locale" RUN_BOUNDED_PGID_FILE="${RUN_BOUNDED_PGID_FILE:-}" \
        run_bounded "${ARC_TIMEOUT_S:-7200}" "${ARC_TIMEOUT_GRACE_S:-120}" "$log" \
        bash "$arc_root/test/install-recovery/arcs/${slug}-arc.sh" "statbus-arc-${slug}" || rc=$?
    # rc 125 = run_bounded could NOT empty the arc's process group: something
    # this job owns is still running in a guest. Admission capacity and the
    # marker stay claimed (the caller must not release the marker either) until
    # the caller reaps it; the stale sweep is the net if the caller dies.
    if [ "$rc" -ne 125 ]; then
        # Normal exit (0, 1, 124, 130..143): run_bounded emptied the group, so
        # its id is dead and may be REUSED by an unrelated process. Drop the
        # persisted id now so no later cleanup can ever signal it. Only rc 125
        # (group NOT emptied) keeps it, as ownership evidence for the reaper.
        [ -z "${RUN_BOUNDED_PGID_FILE:-}" ] || rm -f "$RUN_BOUNDED_PGID_FILE"
        lxd_slot_release "$LXD_HOST" "$slot" "$marker"
    else
        echo "✗ arc $slug: owned process group still alive; slot $slot and marker stay held" >>"$log"
    fi
    [ "$rc" -ne 124 ] || echo "✗ arc $slug exceeded ${ARC_TIMEOUT_S:-7200}s and was terminated" >>"$log"
    verdict=$(lxd_arc_verdict "$log" "$rc")
    echo "$verdict"
    # Return the ACTUAL rc (0 only for PASS) so callers can tell 125 from 1.
    [ "$verdict" != PASS ] || return 0
    [ "$rc" -ne 0 ] || rc=1
    return "$rc"
}

# ── ownership state + always-reap (workflow "Reap THIS arc" step) ───────────
# A job that is cancelled or killed WITHOUT running its EXIT trap can leave a
# running local process group, a fork, a marker and a host slot. The job
# persists what it owns BEFORE acquiring anything (state file, e.g. under
# RUNNER_TEMP), and the always-step calls lxd_arc_reap_own, the single
# authority that frees it:
#   1. delete ONLY this job's own fork,
#   2. stop the owned local process group and VERIFY it is empty,
#   3. only then release its slots and its marker.
# If the group cannot be shown empty, marker and slots are KEPT (never hand
# capacity to a sibling while owned processes may still run); the host stale
# sweep is the last net. Returns 0 = everything released, 1 = ownership kept.
lxd_arc_state_write() {
    local file=$1 host=$2 marker=$3 pgid_file=$4
    [[ "$marker" =~ ^[a-zA-Z0-9._-]+$ ]] || return 2
    printf 'host=%s\nmarker=%s\npgid_file=%s\n' "$host" "$marker" "$pgid_file" > "$file.tmp" && mv "$file.tmp" "$file"
}
lxd_arc_reap_own() {
    local state=$1 fork=$2 host='' marker='' pgid_file='' k v pgid=0 rc=0
    [ -f "$state" ] || { echo "reap: no ownership state $state (nothing acquired)"; return 0; }
    while IFS='=' read -r k v; do
        case "$k" in host) host=$v ;; marker) marker=$v ;; pgid_file) pgid_file=$v ;; esac
    done < "$state"
    [[ "$marker" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "reap: invalid marker in $state" >&2; return 1; }
    if [ -n "$fork" ] && [ -n "$host" ]; then
        _lxd_marker_ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
            "if lxc info '$fork' >/dev/null 2>&1; then lxc delete '$fork' --force; fi" || echo "reap: fork delete failed (continuing to group check)" >&2
    fi
    if [ -n "$pgid_file" ] && [ -s "$pgid_file" ]; then
        pgid=$(cat "$pgid_file")
        stop_group "$pgid" "${ARC_REAP_GRACE_S:-10}" || rc=1
    fi
    if [ "$rc" -ne 0 ]; then
        echo "::error::reap: owned process group $pgid could not be emptied; marker $marker and its slots stay held" >&2
        return 1
    fi
    lxd_slot_release_owned "$host" "$marker" || { echo "reap: slot release failed; marker kept" >&2; return 1; }
    lxd_marker_release "$host" "$marker" || true
    rm -f "$pgid_file" "$state"
    echo "reap: released marker $marker and its slots"
}
