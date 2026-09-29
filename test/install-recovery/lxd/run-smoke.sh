#!/usr/bin/env bash
# Smoke owns the checkpoint catalog consumed by fault forks and upgrade arcs.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
TAG=${1:?usage: run-smoke.sh <candidate-rc-tag> <0-happy-install|0-happy-upgrade>}
SCENARIO=${2:?smoke scenario required}
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || exit 2
case "$SCENARIO" in 0-happy-install|0-happy-upgrade) ;; *) echo "Unknown smoke scenario: $SCENARIO" >&2; exit 2 ;; esac
[ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse "$TAG^{commit}")" ] || {
    echo "REFUSE: smoke checkout must be pinned to $TAG" >&2; exit 2;
}
export LXD_CANDIDATE=$TAG HARNESS_LXD_BACKEND=1 INSTALL_TARGET_TAG=$TAG
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"
source "$ROOT/ops/lxd-fleet/marker.sh"
# Smoke, the fault driver and (from M3 on) arc matrix jobs each hold their
# OWN marker while genuinely active, so the reaper never deletes the box
# out from under a job it cannot see (a single shared marker file cannot
# represent "more than one job is active" - review §1e). Best-effort release
# on any exit, including a failed/cancelled run.
MARKER_ID="${GITHUB_RUN_ID:-manual}-smoke-${SCENARIO}-$$"
lxd_marker_acquire "$LXD_HOST" "$MARKER_ID"
trap 'lxd_marker_release "$LXD_HOST" "$MARKER_ID"' EXIT
case "$SCENARIO" in
    0-happy-install)
        lxd_base_for_candidate "$TAG" hardened-nothing-installed
        # The scenario's own real tagged install captures a provisional
        # checkpoint after assertions and before the operator-tuning phase,
        # then promotes it to the real checkpoint as its last act, once
        # every assertion (including Phase 2) has passed.
        export HARNESS_LXD_CHECKPOINT=1
        ;;
    0-happy-upgrade)
        # 0-happy-upgrade.sh itself defaults HARNESS_UPGRADE_CHANNEL to
        # prerelease (the Norway hop this cell proves), but that default only
        # takes effect once the SCENARIO script runs, below - after the
        # baseline base is already built. Set it here so
        # _lxd_build_base_for_candidate installs the baseline on the same
        # channel the scenario declares, not the harness-wide stable default
        # (review §1a.5).
        export HARNESS_UPGRADE_CHANNEL=prerelease
        # review N1: the checkpoint identity, not just the channel used to
        # BUILD it, must carry a suffix that only THIS producer emits.
        # HARNESS_UPGRADE_CHANNEL is the wrong signal to key the suffix on:
        # the fault fleet's own delegators (5-install-disk-threshold-repair,
        # 0-https-only-egress) also set it to prerelease while resolving
        # through lxd_checkpoint_for_scenario's identical baseline branch,
        # and must still land on the fault fleet's unsuffixed stable name.
        # LXD_BASELINE_CHECKPOINT_SUFFIX is an independent, explicit identity
        # knob only this smoke leg sets. lxd_checkpoint_for_scenario's
        # baseline branch appends it; deriving `checkpoint` FROM that
        # function (instead of re-spelling the same string here) is what
        # keeps producer and consumer from diverging again — this scenario's
        # own bootstrap_install_test_vm call resolves through the exact same
        # function.
        export LXD_BASELINE_CHECKPOINT_SUFFIX=-pre
        checkpoint=$(lxd_checkpoint_for_scenario "$SCENARIO")
        lxd_base_for_candidate "$TAG" "$checkpoint"
        ;;
esac
bash "$ROOT/test/install-recovery/scenarios/$SCENARIO.sh" "statbus-recovery-$SCENARIO"
case "$SCENARIO" in
    0-happy-install) checkpoint="installed-$TAG-standalone" ;;
    0-happy-upgrade) checkpoint=$(lxd_checkpoint_for_scenario "$SCENARIO") ;;
esac
base=$(_lxd_name "$TAG-$checkpoint")
[ "$(_lxd_host lxc config get "$base" image.version)" = 26.04 ]
_lxd_host lxc info "$base" | grep -qE '^\| checkpoint +\|' || {
    echo "Smoke passed without its required checkpoint: $base/checkpoint" >&2; exit 1;
}
echo "PASS: $SCENARIO; checkpoint=$base/checkpoint"
