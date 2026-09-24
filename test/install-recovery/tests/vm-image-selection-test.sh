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
grep -Fq 'if [ "${HARNESS_HTTPS_ONLY_EGRESS:-0}" != "1" ]; then' "$expected" \
    || { echo 'FAIL: 0-happy-upgrade does not scope its 24.04 pin to its own entry point' >&2; exit 1; }

https_only="$SCENARIOS/0-https-only-egress.sh"
grep -Fq 'export HARNESS_HTTPS_ONLY_EGRESS=1' "$https_only" \
    || { echo 'FAIL: HTTPS-only scenario does not select the shared-flow 26.04 path' >&2; exit 1; }
grep -Fq 'HARNESS_SKIP_DEFAULT' "$https_only" \
    || { echo 'FAIL: HTTPS-only scenario is not pinned as on-demand until its corrected rule passes a real VM run' >&2; exit 1; }
if grep -Eq 'ubuntu-24\.04|HARNESS_VM_IMAGE=' "$https_only"; then
    echo 'FAIL: HTTPS-only scenario overrides the Ubuntu 26.04 harness default' >&2
    exit 1
fi

echo 'PASS: only the 0-happy-upgrade entry point uses Ubuntu 24.04; HTTPS-only is on-demand and resolves to Ubuntu 26.04'
