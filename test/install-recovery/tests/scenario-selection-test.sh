#!/bin/bash
# Offline contract for the release-default scenario set. On-demand scenarios
# remain discoverable by an explicit selector but must not enter the full suite.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RUNNER="$ROOT/test/install-recovery/run.sh"
SCENARIOS=(
    0-https-only-egress
    5-install-source-image-identity-proof
)

default_selected=$(bash "$RUNNER" --print-selected)
for scenario in "${SCENARIOS[@]}"; do
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

echo "PASS: on-demand scenarios are excluded by default and remain runnable explicitly"
