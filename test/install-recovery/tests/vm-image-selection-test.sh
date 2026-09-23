#!/bin/bash
# Offline contract for the harness OS matrix. Real compatibility is established
# only by the paid VM workflows after the commit is pushed and its images exist.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
BOOTSTRAP="$ROOT/test/install-recovery/lib/vm-bootstrap.sh"
SCENARIOS="$ROOT/test/install-recovery/scenarios"
ARCS="$ROOT/test/install-recovery/arcs"

grep -Fq 'HARNESS_VM_IMAGE="${HARNESS_VM_IMAGE:-ubuntu-26.04}"' "$BOOTSTRAP" \
    || { echo 'FAIL: vm-bootstrap does not default HARNESS_VM_IMAGE to ubuntu-26.04' >&2; exit 1; }

if rg -n 'HCLOUD_IMAGE' "$ROOT/test/install-recovery/lib" "$SCENARIOS" "$ARCS"; then
    echo 'FAIL: legacy HCLOUD_IMAGE selector remains in the harness' >&2
    exit 1
fi

overrides=$(rg -l '^[[:space:]]*HARNESS_VM_IMAGE=' "$SCENARIOS" "$ARCS" | sort)
override_count=$(printf '%s\n' "$overrides" | grep -c .)
[ "$override_count" -eq 1 ] || {
    printf 'FAIL: expected exactly one scenario/arc VM image override, found %d:\n' "$override_count" >&2
    printf '  %s\n' "$overrides" >&2
    exit 1
}

expected="$SCENARIOS/0-happy-upgrade.sh"
[ "$overrides" = "$expected" ] \
    || { echo "FAIL: the sole VM image override is $overrides, expected $expected" >&2; exit 1; }
grep -Fq 'HARNESS_VM_IMAGE="ubuntu-24.04"' "$expected" \
    || { echo 'FAIL: 0-happy-upgrade is not explicitly pinned to ubuntu-24.04' >&2; exit 1; }

echo 'PASS: Ubuntu 26.04 is the harness default and only 0-happy-upgrade uses Ubuntu 24.04'
