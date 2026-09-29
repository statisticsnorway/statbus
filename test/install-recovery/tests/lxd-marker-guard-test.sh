#!/usr/bin/env bash
# Offline contract (review M-H3a): lxd_marker_acquire must refuse (not
# silently acquire) while the reaper or host hardening holds its own marker.
# A prior version was a bare `mkdir -p && touch` with no check at all - a real
# regression against the single-file marker it replaced (the old fault-driver
# acquire DID check fleet-hardening.active). Without the check, a starter
# could win the race and acquire its slot in the window between reap.sh's own
# touch of /root/fleet-reaping and its actual delete (reap.sh deletes OUTSIDE
# its flock, after releasing it), or during host hardening's sshd/UFW edits.
#
# Runs the REAL lxd_marker_acquire/lxd_marker_release functions, with
# _lxd_marker_ssh substituted for a local shell that rewrites /root/... to a
# throwaway tmpdir and a `flock` stub that just execs its command (this dev
# machine may have no `flock` binary at all; the embedded remote script's own
# `set -euo pipefail; [ A ] && [ B ] || { exit 1; }` guard logic is what this
# test actually verifies, not host-level lock contention, which needs the
# real box).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/ops/lxd-fleet/marker.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/root"
flock() { shift 1; "$@"; }
export -f flock
_lxd_marker_ssh() {
    shift 5 # drop -o BatchMode=yes -o StrictHostKeyChecking=accept-new <host>
    local cmd=$1
    cmd=${cmd//\/root\//$TMP\/root\/}
    bash -c "$cmd"
}

lxd_marker_acquire fake-host testid1
[ -e "$TMP/root/fleet-active/testid1" ] || { echo 'FAIL: marker file not created' >&2; exit 1; }
[ -s "$TMP/root/last-fleet-activity" ] || { echo 'FAIL: activity timestamp not stamped' >&2; exit 1; }
echo 'PASS: clean acquire creates the marker and stamps activity'

touch "$TMP/root/fleet-reaping"
if lxd_marker_acquire fake-host testid2; then
    echo 'FAIL: acquired while fleet-reaping is active (M-H3a regression)' >&2; exit 1
fi
[ ! -e "$TMP/root/fleet-active/testid2" ] || { echo 'FAIL: marker created despite refusal' >&2; exit 1; }
rm -f "$TMP/root/fleet-reaping"
echo 'PASS: acquire refuses while fleet-reaping is active'

touch "$TMP/root/fleet-hardening.active"
if lxd_marker_acquire fake-host testid3; then
    echo 'FAIL: acquired while fleet-hardening.active is set (M-H3a regression)' >&2; exit 1
fi
[ ! -e "$TMP/root/fleet-active/testid3" ] || { echo 'FAIL: marker created despite refusal' >&2; exit 1; }
rm -f "$TMP/root/fleet-hardening.active"
echo 'PASS: acquire refuses while host hardening is active'

lxd_marker_release fake-host testid1
[ ! -e "$TMP/root/fleet-active/testid1" ] || { echo 'FAIL: release did not remove the marker' >&2; exit 1; }
echo 'PASS: release removes the marker'
