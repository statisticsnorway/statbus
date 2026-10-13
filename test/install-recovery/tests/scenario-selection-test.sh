#!/bin/bash
# Offline contract for the release-default scenario set. On-demand scenarios
# remain discoverable by an explicit selector but must not enter the full suite.
# Default scenarios must be in the full suite (STATBUS-357 AC 4 / STATBUS-485:
# 0-https-only-egress rejoined after its first green real LXD run).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RUNNER="$ROOT/test/install-recovery/run.sh"
ON_DEMAND=(
    5-install-source-image-identity-proof
)
DEFAULT=(
    0-https-only-egress
)

default_selected=$(bash "$RUNNER" --print-selected)
for scenario in "${ON_DEMAND[@]}"; do
    if printf '%s\n' "$default_selected" | grep -Fxq "$scenario"; then
        echo "FAIL: $scenario remains in the default install-recovery set" >&2
        exit 1
    fi

    on_demand_selected=$(bash "$RUNNER" --print-selected "$scenario")
    [ "$on_demand_selected" = "$scenario" ] || {
        echo "FAIL: explicit selector did not retain $scenario as on-demand; got: $on_demand_selected" >&2
        exit 1
    }
done

for scenario in "${DEFAULT[@]}"; do
    printf '%s\n' "$default_selected" | grep -Fxq "$scenario" || {
        echo "FAIL: $scenario is missing from the default install-recovery set" >&2
        exit 1
    }
done

echo "PASS: on-demand scenarios are excluded by default and remain runnable explicitly; default scenarios are selected"
