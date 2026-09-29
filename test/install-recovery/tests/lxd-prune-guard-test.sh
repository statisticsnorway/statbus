#!/usr/bin/env bash
# Offline contract (review H3): _lxd_prune_other_bases embeds a guard clause
# on the FLEET HOST that must refuse (exit 1) when no occupancy marker is
# held, rather than silently falling through to the destructive prune loop.
# A prior version wrote this as a bare `A && B && C` statement list, which is
# NOT a guard under `set -e`: errexit only trips on the FAILURE of the LAST
# command in an && list, so an empty $active (no marker held) made the whole
# list evaluate false WITHOUT tripping errexit, and execution fell through to
# `lxc list` regardless (verified live on the real box before the `||
# { ...; exit 1; }` fix — see the progress log).
#
# This runs the REAL embedded guard script (extracted from the running
# function, not a paraphrase) as a genuine local subprocess: the same
# `_lxd_host` stub technique lxd-smoke-checkpoint-test.sh uses for its rerun-
# safe replace probe, which intercepts the `flock /root/fleet-run.lock`
# prefix and directly execs the rest so the embedded script actually runs.
# Never contacts the LXD host. The marker paths (/root/fleet-active, etc.)
# are real absolute paths the guard checks with plain `-e`/`ls -A`; on a
# non-root dev machine or CI runner they simply do not exist, which IS the
# "empty marker directory" state this test needs — no fixture setup required.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"

[ ! -e /root/fleet-active ] && [ ! -e /root/fleet-reaping ] && [ ! -e /root/fleet-hardening.active ] || {
    echo "SKIP: this test machine has real /root/fleet-* state; refusing to assume 'empty marker directory'" >&2
    exit 1
}

lxc() { echo "UNEXPECTED lxc call: $*" >&2; return 1; }
export -f lxc
calls=()
_lxd_host() {
    calls+=("$*")
    if [ "$1" = flock ]; then
        shift 2
        set +e
        "$@"
        rc=$?
        set -e
        return "$rc"
    fi
}

if _lxd_prune_other_bases v2026.09.3-rc.16; then
    echo "FAIL: prune proceeded with an empty marker directory (H3 regression)" >&2
    exit 1
fi
echo "PASS: prune refuses (rc=1) with no active occupancy marker, never reaching lxc list"
