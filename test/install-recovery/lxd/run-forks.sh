#!/usr/bin/env bash
# STATBUS-417 manual parallel parity driver. --scenario slug may be repeated.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
TAG=${1:?usage: run-forks.sh <tag> [--scenario slug ...]}
shift
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || exit 2
export LXD_CANDIDATE=$TAG
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"
source "$ROOT/test/install-recovery/lxd/verdict.sh"
source "$ROOT/test/install-recovery/lxd/fleet-status.sh"
PINNED_ROOT="${JCODE_SCRATCH_DIR:?JCODE_SCRATCH_DIR required}/lxd-s2-pinned-${TAG//[^a-zA-Z0-9-]/-}"
if [ ! -d "$PINNED_ROOT/.git" ] && [ ! -f "$PINNED_ROOT/.git" ]; then
    git -C "$ROOT" worktree add --detach "$PINNED_ROOT" "$TAG"
fi
[ "$(git -C "$PINNED_ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse "$TAG^{commit}")" ] || {
    echo 'REFUSE: pinned worktree HEAD is not candidate tag' >&2; exit 2;
}
RUN_DIR="$PINNED_ROOT/tmp/lxd-stage2-${TAG}-$(date -u +%Y%m%dT%H%M%S)"
mkdir -p "$RUN_DIR/shadow/lib" "$RUN_DIR/shadow/scenarios"
printf 'scenario\tvm_verdict\tvm_wall_s\tlxd_verdict\tlxd_wall_s\tlxd_rc\tcheckpoint\n' > "$RUN_DIR/comparison.tsv"
phase=setup
finalize() {
    local rc=$? slug
    trap - EXIT
    for slug in "${scenarios[@]+"${scenarios[@]}"}"; do
        [ -f "$RUN_DIR/$slug.row" ] || continue
        cat "$RUN_DIR/$slug.row" >> "$RUN_DIR/comparison.tsv"
    done
    if [ "$rc" -ne 0 ]; then
        printf '%s\t\t\tPHASE_FAILED\t\t%s\t\n' "$phase" "$rc" >> "$RUN_DIR/comparison.tsv"
        printf 'STATUS=FAILED\nPHASE=%s\nDETAIL=exit %s\n' "$phase" "$rc" > "$RUN_DIR/fleet-status.txt"
    fi
    if [ -n "${LXD_FLEET_ARTIFACT_DIR:-}" ]; then
        mkdir -p "$LXD_FLEET_ARTIFACT_DIR"
        cp "$RUN_DIR/comparison.tsv" "$LXD_FLEET_ARTIFACT_DIR/"
        find "$RUN_DIR" -maxdepth 1 -name '*.log' -exec cp {} "$LXD_FLEET_ARTIFACT_DIR/" \;
        [ ! -f "$RUN_DIR/fleet-status.txt" ] || cp "$RUN_DIR/fleet-status.txt" "$LXD_FLEET_ARTIFACT_DIR/"
    fi
}
scenarios=()
trap finalize EXIT
if [ -n "${LXD_FLEET_ARTIFACT_DIR:-}" ]; then
    mkdir -p "$LXD_FLEET_ARTIFACT_DIR"
    echo "$RUN_DIR" > "$LXD_FLEET_ARTIFACT_DIR/run-dir.txt"
fi
# The remote tag lookup is deliberately repeated at each batch boundary, not
# read from the checkout made when this workflow started.
fresh_fork_batch() {
    local tags newest
    if ! tags=$(git -C "$ROOT" ls-remote --tags --refs origin 'v*-rc.*'); then
        echo '::warning title=RC freshness unknown::remote lookup failed; proceeding' >&2
        return 0
    fi
    newest=$(printf '%s\n' "$tags" | awk '$2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$/ {sub(/^refs\/tags\//, "", $2); print $2}' | LC_ALL=C sort -V | tail -n 1)
    if [ -n "$newest" ] && [ "$newest" != "$TAG" ] &&
       [ "$(printf '%s\n%s\n' "$TAG" "$newest" | LC_ALL=C sort -V | tail -n 1)" = "$newest" ]; then
        echo "SUPERSEDED by $newest before next fork batch" >&2
        printf 'STATUS=SUPERSEDED\nDETAIL=newer tag %s\n' "$newest" > "$RUN_DIR/fleet-status.txt"
        return 1
    fi
    return 0
}
# A shadow bootstrap selects the backend without modifying original scenario assertions.
for lib in "$PINNED_ROOT"/test/install-recovery/lib/*; do
    [ "${lib##*/}" = vm-bootstrap.sh ] && continue
    ln -s "$lib" "$RUN_DIR/shadow/lib/${lib##*/}"
done
ln -s "$ROOT/test/install-recovery/lib/lxd-backend.sh" "$RUN_DIR/shadow/lib/vm-bootstrap.sh"
for scenario in "$PINNED_ROOT"/test/install-recovery/scenarios/*.sh; do
    ln -s "$scenario" "$RUN_DIR/shadow/scenarios/${scenario##*/}"
done
scenarios=()
if [ "$#" -eq 0 ]; then
    for script in "$PINNED_ROOT"/test/install-recovery/scenarios/*.sh; do
        slug=${script##*/}; slug=${slug%.sh}
        case "$slug" in 0-happy-*) continue ;; esac
        # Same file-content marker as run.sh's default/full discovery. Explicit
        # --scenario still selects on-demand cases.
        if grep -q HARNESS_SKIP_DEFAULT "$script"; then continue; fi
        scenarios+=("$slug")
    done
else
    while [ "$#" -gt 0 ]; do
        [ "$1" = --scenario ] && [ "$#" -ge 2 ] || { echo 'Expected --scenario slug' >&2; exit 2; }
        scenarios+=("$2"); shift 2
    done
fi
# A slug owns one container, log and row per invocation.
# Portable duplicate check: macOS ships bash 3.2 (no associative arrays) and
# this driver runs from developer machines as well as CI.
dup=$(printf '%s\n' "${scenarios[@]}" | sort | uniq -d)
[ -z "$dup" ] || { echo "Duplicate scenario slug: $dup" >&2; exit 2; }
# Build each distinct checkpoint only on demand, serially. Never race two builders.
checkpoints=()
for slug in "${scenarios[@]}"; do
    phase="checkpoint-$slug"
    if ! fresh_fork_batch; then
        exit 0
    fi
    checkpoint=$(lxd_checkpoint_for_scenario "$slug")
    found=0
    for existing in ${checkpoints[@]+"${checkpoints[@]}"}; do
        [ "$existing" = "$checkpoint" ] && found=1
    done
    if [ "$found" -eq 0 ]; then
        checkpoints+=("$checkpoint")
        lxd_base_for_candidate "$TAG" "$checkpoint" >"$RUN_DIR/base-$checkpoint.log" 2>&1 || {
            echo "BASE FAILED: $checkpoint; see $RUN_DIR/base-$checkpoint.log" >&2; exit 1;
        }
    fi
done
MAX_PARALLEL=${LXD_PARALLEL:-6}
[[ "$MAX_PARALLEL" =~ ^[1-8]$ ]] || { echo 'LXD_PARALLEL must be 1..8' >&2; exit 2; }
pids=()
for slug in "${scenarios[@]}"; do
    phase="fork-$slug"
    if ! fresh_fork_batch; then break; fi
    checkpoint=$(lxd_checkpoint_for_scenario "$slug")
    (
        started=$(date +%s)
        name="s2-${TAG//[^a-zA-Z0-9-]/-}-$slug"
        # Only our own prefixed instance, reset before every invocation.
        if _lxd_host lxc info "$name" >/dev/null 2>&1; then _lxd_host lxc delete "$name" --force; fi
        rc=0
        LXD_CANDIDATE="$TAG" LXD_LOG_DIR="$RUN_DIR" bash "$RUN_DIR/shadow/scenarios/$slug.sh" "statbus-recovery-$slug" >"$RUN_DIR/$slug.log" 2>&1 || rc=$?
        verdict=$(lxd_scenario_verdict "$RUN_DIR/$slug.log" "$rc")
        if [ "$slug" = 4-install-40gb-disk ] && [ "$verdict" = PASS ]; then
            if ! awk '$1 ~ /^\/dev\// && $2 == "40G" {found=1} END {exit !found}' "$RUN_DIR/$slug.log"; then
                verdict=INVALID
                echo 'INVALID: guest df did not expose the 40G filesystem; LXD Btrfs quota alone is not a 40G VM proof' >> "$RUN_DIR/$slug.log"
            fi
        fi
        printf '%s\t\t\t%s\t%s\t%s\t%s\n' "$slug" "$verdict" "$(( $(date +%s) - started ))" "$rc" "$checkpoint" > "$RUN_DIR/$slug.row"
    ) &
    pids+=("$!")
    if [ "${#pids[@]}" -ge "$MAX_PARALLEL" ]; then
        wait "${pids[0]}" || true
        pids=("${pids[@]:1}")
    fi
done
for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid" || true; done
phase=verdict
echo "Logs and parity template: $RUN_DIR"
fleet_status_read "$RUN_DIR/fleet-status.txt"
[ "$FLEET_STATUS" != SUPERSEDED ] || exit 0
for slug in "${scenarios[@]}"; do
    [ -f "$RUN_DIR/$slug.row" ] || { echo "Missing result: $slug" >&2; exit 1; }
    awk -F '\t' '$4 != "PASS" {exit 1}' "$RUN_DIR/$slug.row" || exit 1
done
printf 'STATUS=PASSED\n' > "$RUN_DIR/fleet-status.txt"
