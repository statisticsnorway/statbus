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
PINNED_ROOT="${JCODE_SCRATCH_DIR:?JCODE_SCRATCH_DIR required}/lxd-s2-pinned-${TAG//[^a-zA-Z0-9-]/-}"
if [ ! -d "$PINNED_ROOT/.git" ] && [ ! -f "$PINNED_ROOT/.git" ]; then
    git -C "$ROOT" worktree add --detach "$PINNED_ROOT" "$TAG"
fi
[ "$(git -C "$PINNED_ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse "$TAG^{commit}")" ] || {
    echo 'REFUSE: pinned worktree HEAD is not candidate tag' >&2; exit 2;
}
RUN_DIR="$PINNED_ROOT/tmp/lxd-stage2-${TAG}-$(date -u +%Y%m%dT%H%M%S)"
mkdir -p "$RUN_DIR/shadow/lib" "$RUN_DIR/shadow/scenarios"
# A shadow bootstrap selects the backend without modifying original scenario assertions.
for lib in "$ROOT"/test/install-recovery/lib/*.sh; do
    [ "${lib##*/}" = vm-bootstrap.sh ] && continue
    ln -s "$lib" "$RUN_DIR/shadow/lib/${lib##*/}"
done
ln -s "$ROOT/test/install-recovery/lib/lxd-backend.sh" "$RUN_DIR/shadow/lib/vm-bootstrap.sh"
for scenario in "$ROOT"/test/install-recovery/scenarios/*.sh; do
    ln -s "$scenario" "$RUN_DIR/shadow/scenarios/${scenario##*/}"
done
scenarios=()
if [ "$#" -eq 0 ]; then
    for script in "$ROOT"/test/install-recovery/scenarios/*.sh; do
        slug=${script##*/}; slug=${slug%.sh}
        case "$slug" in 0-happy-*) continue ;; esac
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
printf 'scenario\tvm_verdict\tvm_wall_s\tlxd_verdict\tlxd_wall_s\tlxd_rc\tcheckpoint\n' > "$RUN_DIR/comparison.tsv"
MAX_PARALLEL=${LXD_PARALLEL:-6}
[[ "$MAX_PARALLEL" =~ ^[1-8]$ ]] || { echo 'LXD_PARALLEL must be 1..8' >&2; exit 2; }
pids=()
for slug in "${scenarios[@]}"; do
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
for slug in "${scenarios[@]}"; do cat "$RUN_DIR/$slug.row" >> "$RUN_DIR/comparison.tsv"; done
cat "$RUN_DIR/comparison.tsv"
echo "Logs and parity template: $RUN_DIR"
awk -F '\t' 'NR > 1 && $4 != "PASS" {bad=1} END {exit bad}' "$RUN_DIR/comparison.tsv"
