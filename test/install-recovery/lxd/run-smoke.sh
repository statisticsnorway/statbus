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
        source "$ROOT/test/install-recovery/lib/release-baseline.sh"
        baseline=$(select_release_baseline_from_repo "$ROOT" "$TAG")
        # 0-happy-upgrade.sh itself defaults HARNESS_UPGRADE_CHANNEL to
        # prerelease (the Norway hop this cell proves), but that default only
        # takes effect once the SCENARIO script runs, below - after the
        # baseline base is already built. Set it here so
        # _lxd_build_base_for_candidate installs the baseline on the same
        # channel the scenario declares, not the harness-wide stable default
        # (review §1a.5).
        export HARNESS_UPGRADE_CHANNEL=prerelease
        # review B3: the channel rides in the checkpoint NAME, not only in a
        # config key checked at build time. The fault fleet's own fallback
        # build (lxd_checkpoint_for_scenario -> lxd_base_for_candidate, no
        # HARNESS_UPGRADE_CHANNEL set, so channel=stable) wants the SAME
        # instance name "installed-$baseline-standalone" this job would
        # otherwise also claim for a DIFFERENT (prerelease) box state. Two
        # producers, one candidate tag, one baseline tag, two genuinely
        # different .env.config contents cannot share one checkpoint name:
        # whichever runs second finds a base "built for the other channel"
        # and REFUSES (a real run, not hypothetical - the fault fleet always
        # runs after smoke). Suffix only the non-stable identity; the fault
        # fleet's stable name is untouched, so its own parity history stays
        # valid.
        checkpoint="installed-$baseline-standalone-pre"
        lxd_base_for_candidate "$TAG" "$checkpoint"
        ;;
esac
bash "$ROOT/test/install-recovery/scenarios/$SCENARIO.sh" "statbus-recovery-$SCENARIO"
case "$SCENARIO" in
    0-happy-install) checkpoint="installed-$TAG-standalone" ;;
    0-happy-upgrade) checkpoint="installed-$baseline-standalone-pre" ;;
esac
base=$(_lxd_name "$TAG-$checkpoint")
[ "$(_lxd_host lxc config get "$base" image.version)" = 26.04 ]
_lxd_host lxc info "$base" | grep -qE '^\| checkpoint +\|' || {
    echo "Smoke passed without its required checkpoint: $base/checkpoint" >&2; exit 1;
}
echo "PASS: $SCENARIO; checkpoint=$base/checkpoint"
