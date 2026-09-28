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
# before this file) shadows `ssh` with a shim that refuses any destination
# other than the current fork's guest IP (its own VM_IP scoping guard) - a
# bare `ssh` call here would be refused with "does not match fork IP" the
# moment both files are sourced together, which is exactly run-smoke.sh's
# case. `command` forces the real ssh binary regardless of what a caller has
# sourced.
lxd_marker_acquire() {
    local host=$1 id=$2
    [[ "$id" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Invalid marker id: $id" >&2; return 2; }
    command ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
        "mkdir -p /root/fleet-active && touch '/root/fleet-active/$id' && date +%s > /root/last-fleet-activity"
}
lxd_marker_release() {
    local host=$1 id=$2
    [[ "$id" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Invalid marker id: $id" >&2; return 2; }
    command ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" \
        "rm -f '/root/fleet-active/$id'; date +%s > /root/last-fleet-activity" || true
}
