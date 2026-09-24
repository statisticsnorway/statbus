#!/bin/bash
# Offline contract for the release-default scenario set. On-demand scenarios
# remain discoverable by an explicit selector but must not enter the full suite.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RUNNER="$ROOT/test/install-recovery/run.sh"
SCENARIO=0-https-only-egress

default_selected=$(bash "$RUNNER" --print-selected)
if printf '%s\n' "$default_selected" | grep -Fxq "$SCENARIO"; then
    echo "FAIL: $SCENARIO remains in the default install-recovery set" >&2
    exit 1
fi

on_demand_selected=$(bash "$RUNNER" --print-selected "$SCENARIO")
[ "$on_demand_selected" = "$SCENARIO" ] || {
    echo "FAIL: explicit selector did not retain $SCENARIO as on-demand; got: $on_demand_selected" >&2
    exit 1
}

echo "PASS: $SCENARIO is excluded by default and remains runnable on demand"
