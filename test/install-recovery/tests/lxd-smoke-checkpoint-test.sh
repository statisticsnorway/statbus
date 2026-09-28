#!/usr/bin/env bash
# Offline boundary test: a real smoke scenario may publish only its own healthy
# running fork as a PROVISIONAL checkpoint (checkpoint-pending, copied while
# running so its own /tmp/env-config survives for the later operator-tuning
# phase), tag it with provenance, then resume its operator checks against the
# still-running source. lxd_promote_checkpoint (tested separately below) is
# the scenario's separate LAST act that makes it visible to forks.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
export LXD_CANDIDATE=v2026.09.3-rc.16 LXD_BASE_PREFIX=s2-26
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"
VM_NAME=s2-v2026-09-3-rc-16-0-happy-install
export LXD_OWNED_BY_THIS_RUN=1 # consumed by lxd_snapshot_installed's ownership guard
BASE=s2-26-v2026-09-3-rc-16-installed-v2026-09-3-rc-16-standalone
calls=()
_lxd_ready() { calls+=("ready:$1"); }
_lxd_host() {
    calls+=("$*")
    # The rerun-safe replace probe runs inside `live=$(_lxd_host ...)`: a
    # command substitution subshell. Any `calls+=` done there is invisible to
    # THIS array (bash subshells copy, never share, array state) - so the
    # probe call itself cannot be asserted on through `calls`. Its behavior is
    # exercised directly on the real box by lxd-smoke-checkpoint-test's
    # M2' hand verification (see the progress log), not here. This mock's
    # empty stdout on the probe path (no case below emits anything) is what
    # matters: it makes lxd_snapshot_installed see "no live fork", the
    # first-ever-run path this test is about.
    if [ "$1 $2" = 'lxc info' ]; then return 1; fi
}
lxd_snapshot_installed "$LXD_CANDIDATE" "$VM_NAME"
expected=(
    "ready:$VM_NAME"
    "lxc copy $VM_NAME $BASE"
    "lxc snapshot $BASE checkpoint-pending"
    "lxc config set $BASE user.statbus.candidate $LXD_CANDIDATE"
    "lxc config set $BASE user.statbus.producer smoke"
    "lxc config set $BASE user.statbus.run_id manual"
)
for ((i=0; i<${#expected[@]}; i++)); do
    [ "${calls[$i]:-}" = "${expected[$i]}" ] || { printf 'snapshot call %s: expected %s, got %s\n' "$i" "${expected[$i]}" "${calls[$i]:-MISSING}" >&2; exit 1; }
done
[ "${#calls[@]}" -eq "${#expected[@]}" ]
VM_NAME=foreign-instance
if lxd_snapshot_installed "$LXD_CANDIDATE" s2-v2026-09-3-rc-16-0-happy-install; then
    echo 'foreign fork was allowed to publish a checkpoint' >&2; exit 1
fi
echo 'PASS: only the owned healthy smoke fork publishes a checkpoint-pending before tuning'

# lxd_promote_checkpoint: the scenario's separate last act. Must refuse
# without a checkpoint-pending snapshot present, and rename (never copy or
# re-snapshot) when one exists. `_lxd_host lxc info "$base" | grep ...` runs
# the info call in a pipeline subshell, so only the rename call (run directly
# in the function body, not piped) is observable through `calls` here.
calls=()
_lxd_host() {
    case "$*" in
        "lxc info $BASE") printf '| checkpoint-pending |\n'; return 0 ;;
        *) calls+=("$*") ;;
    esac
}
lxd_promote_checkpoint "$LXD_CANDIDATE"
[ "${calls[0]}" = "lxc rename $BASE/checkpoint-pending $BASE/checkpoint" ] || {
    echo "promote call 0: expected rename, got ${calls[0]:-MISSING}" >&2; exit 1;
}
[ "${#calls[@]}" -eq 1 ]

_lxd_host() { case "$*" in "lxc info $BASE") printf '\n'; return 0 ;; *) return 1 ;; esac; } # no checkpoint-pending line
if lxd_promote_checkpoint "$LXD_CANDIDATE"; then
    echo 'promote succeeded without a checkpoint-pending snapshot' >&2; exit 1
fi
echo 'PASS: lxd_promote_checkpoint only renames pending -> checkpoint, and refuses without one'
