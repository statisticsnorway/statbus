#!/bin/bash
# Offline contract for the release-default scenario set.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RUNNER="$ROOT/test/install-recovery/run.sh"
SCENARIO=0-https-only-egress

default_selected=$(bash "$RUNNER" --print-selected)
if ! printf '%s\n' "$default_selected" | grep -Fxq "$SCENARIO"; then
    echo "FAIL: $SCENARIO is absent from the default install-recovery set" >&2
    exit 1
fi

on_demand_selected=$(bash "$RUNNER" --print-selected "$SCENARIO")
[ "$on_demand_selected" = "$SCENARIO" ] || {
    echo "FAIL: explicit selector did not select $SCENARIO; got: $on_demand_selected" >&2
    exit 1
}

echo "PASS: $SCENARIO is selected by default and explicitly"
