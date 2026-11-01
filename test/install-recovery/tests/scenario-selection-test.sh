#!/bin/bash
# Offline contract for the release-default scenario set. Every scenario file is
# in the full suite: there is no on-demand scenario (the last one,
# 5-install-cert-repair-via-cert-install, was removed unrun, STATBUS-429).
# Default scenarios must be in the full suite (STATBUS-357 AC 4 / STATBUS-485:
# 0-https-only-egress rejoined after its first green real LXD run).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RUNNER="$ROOT/test/install-recovery/run.sh"
DEFAULT=(
    0-https-only-egress
)

default_selected=$(bash "$RUNNER" --print-selected)
for file in "$ROOT"/test/install-recovery/scenarios/*.sh; do
    scenario=$(basename "$file" .sh)
    printf '%s\n' "$default_selected" | grep -Fxq "$scenario" || {
        echo "FAIL: $scenario is not in the default install-recovery set" >&2
        exit 1
    }
done

for scenario in "${DEFAULT[@]}"; do
    printf '%s\n' "$default_selected" | grep -Fxq "$scenario" || {
        echo "FAIL: $scenario is missing from the default install-recovery set" >&2
        exit 1
    }
done

echo "PASS: every scenario file is in the default set, including the named default scenarios"
