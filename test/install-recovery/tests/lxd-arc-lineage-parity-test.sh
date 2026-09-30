#!/usr/bin/env bash
# Offline parity test (STATBUS-425 M3b): run-arcs.sh's arc_lineage_for mapping
# must never drift from upgrade-arc-harness.yaml's "Resolve fixture lineage
# for the scenario" step — they are two copies of the SAME domain knowledge
# (one bash, one embedded in a workflow's `run:` block) and nothing enforces
# textual parity between them except this test. If a new arc is added with a
# non-"working" lineage in one file and not the other, this catches it before
# a live LXD run silently constructs the wrong fixture (working V instead of
# failing V, wrong terminal state expected, etc — a false green or a
# confusing false red, not a clean failure).
#
# Real reproduction, not asserted-by-inspection: for every real arcs/*-arc.sh
# slug, ask run-arcs.sh's own arc_lineage_for() (sourced, not re-implemented
# here) and the workflow YAML's embedded case statement (extracted with a
# small awk/sed pass, then evaluated by a REAL bash case in a throwaway
# script, not string-matched against the extraction) and require identical
# answers for every slug — a change to either file that breaks parity fails
# this test with a concrete slug/lineage diff, not a description.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/statbus-arc-lineage-parity.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# ── 1. arc_lineage_for, exactly as run-arcs.sh defines it (sourced, not
#      duplicated — a change to the real function is picked up automatically,
#      so this test can only ever drift against the WORKFLOW side). Sourced
#      from a real extracted file, not `source <(...)` process substitution
#      (unreliable under bash 3.2, which this driver must also run under). ──
sed -n '/^arc_lineage_for() {/,/^}/p' "$ROOT/test/install-recovery/lxd/run-arcs.sh" > "$TMP/arc_lineage.sh"
# shellcheck disable=SC1091
source "$TMP/arc_lineage.sh"
type arc_lineage_for >/dev/null 2>&1 || { echo 'FAIL: could not extract arc_lineage_for from run-arcs.sh' >&2; exit 1; }

# ── 2. the workflow's case statement, extracted into a real callable
#      function (not string-matched) so it is exercised by real bash `case`
#      semantics identically to how the workflow itself evaluates it. The
#      workflow's "Resolve fixture lineage" step has a SECOND, unrelated
#      case statement further down (schema-floor's own env-var branch) that
#      also opens on `case "$SCENARIO" in` — sed's /p1/,/p2/ range re-arms
#      after closing and would silently swallow both blocks into one, so
#      this stops at the first `esac` by line number instead of by pattern.
WORKFLOW="$ROOT/.github/workflows/upgrade-arc-harness.yaml"
start_line=$(grep -n 'case "\$SCENARIO" in$' "$WORKFLOW" | head -1 | cut -d: -f1)
[ -n "$start_line" ] || { echo 'FAIL: no case "$SCENARIO" in found in upgrade-arc-harness.yaml' >&2; exit 1; }
end_line=$(tail -n "+$start_line" "$WORKFLOW" | grep -n '^ *esac$' | head -1 | cut -d: -f1)
[ -n "$end_line" ] || { echo 'FAIL: no closing esac found after line '"$start_line" >&2; exit 1; }
end_line=$(( start_line + end_line - 1 ))
{
    echo 'workflow_lineage_for() {'
    echo '    local lineage'
    sed -n "${start_line},${end_line}p" "$WORKFLOW" | sed 's/^ *//; s/\$SCENARIO/$1/'
    echo '    echo "$lineage"'
    echo '}'
} > "$TMP/workflow_lineage.sh"
# shellcheck disable=SC1091
source "$TMP/workflow_lineage.sh"
type workflow_lineage_for >/dev/null 2>&1 || { echo 'FAIL: could not extract the case statement from upgrade-arc-harness.yaml' >&2; cat "$TMP/workflow_lineage.sh" >&2; exit 1; }

# ── 3. every real arc slug must agree between the two. ──────────────────────
fail=0
for script in "$ROOT"/test/install-recovery/arcs/*-arc.sh; do
    slug=${script##*/}; slug=${slug%-arc.sh}
    a=$(arc_lineage_for "$slug")
    b=$(workflow_lineage_for "$slug")
    if [ "$a" != "$b" ]; then
        echo "FAIL: $slug — run-arcs.sh says '$a', upgrade-arc-harness.yaml says '$b'" >&2
        fail=1
    fi
done
[ "$fail" -eq 0 ] || exit 1

# ── 4. the wildcard/default arm must genuinely be 'working' on both sides
#      (a slug that will never exist, so this only exercises the `*)` case —
#      catches a future default-arm edit on one side that the loop above,
#      bounded to today's real arc files, could never see). ────────────────
sentinel=nonexistent-future-arc-slug-never-a-real-file
[ "$(arc_lineage_for "$sentinel")" = working ] || { echo "FAIL: run-arcs.sh's default arm is not 'working'" >&2; exit 1; }
[ "$(workflow_lineage_for "$sentinel")" = working ] || { echo "FAIL: upgrade-arc-harness.yaml's default arm is not 'working'" >&2; exit 1; }

echo 'PASS: run-arcs.sh and upgrade-arc-harness.yaml agree on every arc lineage'
