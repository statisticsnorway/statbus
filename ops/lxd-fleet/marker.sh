#!/usr/bin/env bash
# Shared per-job activity marker for the LXD fleet host. Sourced by every
# script/workflow step that runs work on the box (base.sh, the fault driver,
# smoke's per-scenario steps, future arc jobs).
#
# Multiple jobs (smoke's two scenario jobs, the fault fleet driver, arc matrix
# jobs) can be genuinely active on the box AT THE SAME TIME once faults and
# arcs overlap (STATBUS-425 M4). A single marker FILE is wrong for that: the
# first job to finish would delete the file while a sibling job is still
# running, and the reaper or a drift-recreate could then act on a box that is
# not actually idle. Use a directory of per-job marker files instead;
# "active" means the directory is non-empty. reap.sh, up.sh and
# harden-host.sh already gate on the SAME directory (see their own guards);
# this file is the one place that creates/removes entries in it, so the
# meaning of "active" cannot drift between callers.
#
# id: a name unique to this job invocation, e.g. "${GITHUB_RUN_ID:-manual}-<job>-$$".
# Callers should trap lxd_marker_release on EXIT so a cancelled or killed job
# still frees its slot.
#
# `command ssh`, never bare `ssh`: this talks to the FLEET HOST itself, not a
# guest fork. test/install-recovery/lib/lxd-backend.sh (sourced by run-smoke.sh
# before this file) shadows `ssh` two ways once M3a landed: a bash FUNCTION
# (refuses any destination but the current fork's guest IP) AND, for
# `timeout ssh` support, an EXECUTABLE script placed on PATH ahead of the
# system ssh — `command` only defeats the function shim, not the PATH one
# (STATBUS-425 M3a: this file regressed the exact bug it names below the
# moment lxd-backend.sh grew the executable shim; caught live re-running
# this exact smoke flow before trusting it). _LXD_REAL_SSH, if
# lxd-backend.sh has been sourced, is that file's own absolute-path capture
# of the real binary, resolved before either shim existed — reuse it when
# present; fall back to `command ssh` for any other caller of this file.
_lxd_marker_ssh() {
    if [ -n "${_LXD_REAL_SSH:-}" ]; then
        "$_LXD_REAL_SSH" "$@"
    else
        command ssh "$@"
    fi
}
lxd_marker_acquire() {
    local host=$1 id=$2
    [[ "$id" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Invalid marker id: $id" >&2; return 2; }
    _lxd_marker_ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
        "mkdir -p /root/fleet-active && touch '/root/fleet-active/$id' && date +%s > /root/last-fleet-activity"
}
lxd_marker_release() {
    local host=$1 id=$2
    [[ "$id" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Invalid marker id: $id" >&2; return 2; }
    _lxd_marker_ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
        "rm -f '/root/fleet-active/$id'; date +%s > /root/last-fleet-activity" || true
}
