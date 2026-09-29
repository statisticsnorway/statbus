#!/usr/bin/env bash
# Offline contract (review H1): cleanup_vm must capture failure diagnostics
# BEFORE deleting a red fork, and must read the scenario's actual exit status
# regardless of which of the three VM-harness trap shapes the caller uses:
#   most scenarios:                  'rc=$?; cleanup_vm "$VM_NAME"; exit $rc'
#   rollback-schema-floor-*-arc.sh:  'RC=$?; cleanup_vm "$VM_NAME"; exit $RC'
#   the VM harness's own contract:   cleanup_vm "$VM_NAME" "$explicit_status"
# A prior version only ever read $rc, so the RC=$? callers and any future
# explicit-$2 caller would always see scenario_rc=0 and skip the capture on
# a genuine failure — never reproduced live because no scenario in the
# fault-fleet default suite yet uses RC=$?, only two upgrade arcs do.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"

# LXD_CANDIDATE and LXD_FORK_PREFIX are both read by cleanup_vm's
# namespace-match case pattern, not directly here.
# shellcheck disable=SC2034
LXD_CANDIDATE=v2026.09.3-rc.16
# shellcheck disable=SC2034
LXD_FORK_PREFIX=s2
VM_NAME="s2-v2026-09-3-rc-16-0-happy-install"
# shellcheck disable=SC2034 # Read by cleanup_vm (sourced above), not directly here.
LXD_OWNED_BY_THIS_RUN=1
# shellcheck disable=SC2034 # Read by cleanup_vm.
KEEP_VM=0

calls=()
lxd_capture_failure() { calls+=("capture:$1"); }
_lxd_host() { calls+=("$*"); }

# --- Shape 1: most scenarios' `rc` global, read implicitly ---
calls=()
rc=1
cleanup_vm "$VM_NAME"
[ "${calls[0]:-}" = "capture:$VM_NAME" ] || {
    echo "FAIL (rc shape): expected capture before delete, got: ${calls[*]:-<empty>}" >&2; exit 1;
}
[ "${calls[1]:-}" = "lxc delete $VM_NAME --force" ] || {
    echo "FAIL (rc shape): expected delete after capture, got: ${calls[*]:-<empty>}" >&2; exit 1;
}
echo "PASS: rc=1 (implicit \$rc global) captures before deleting"
unset rc

# --- Shape 2: rollback-schema-floor-*-arc.sh's RC global, read implicitly ---
calls=()
# shellcheck disable=SC2034 # Read by cleanup_vm's ${RC:-0} fallback, not directly here.
RC=1
cleanup_vm "$VM_NAME"
[ "${calls[0]:-}" = "capture:$VM_NAME" ] || {
    echo "FAIL (RC shape): expected capture before delete, got: ${calls[*]:-<empty>}" >&2; exit 1;
}
echo "PASS: RC=1 (implicit \$RC global, rollback-schema-floor's own trap shape) captures before deleting"
unset RC

# --- Shape 3: an explicit $2, the VM harness's own contract
# (tests/partial-allocation-cleanup-test.sh) — must win over any global. ---
calls=()
# shellcheck disable=SC2034 # Deliberately stale rc=0 to prove $2 wins over it.
rc=0 # a caller could genuinely have rc=0 in scope yet still pass an explicit failure
cleanup_vm "$VM_NAME" 1
[ "${calls[0]:-}" = "capture:$VM_NAME" ] || {
    echo "FAIL (explicit \$2): expected capture before delete, got: ${calls[*]:-<empty>}" >&2; exit 1;
}
echo "PASS: an explicit \$2 status is honored (and wins over a stale \$rc=0)"
unset rc

# --- No failure signal anywhere: never capture on a genuine success ---
calls=()
cleanup_vm "$VM_NAME" 0
[ "${#calls[@]}" -eq 1 ] && [ "${calls[0]}" = "lxc delete $VM_NAME --force" ] || {
    echo "FAIL: a clean exit (\$2=0) must delete without capturing, got: ${calls[*]:-<empty>}" >&2; exit 1;
}
echo "PASS: a clean exit deletes without capturing"

echo "PASS: cleanup_vm captures failure diagnostics before deleting, across every trap shape"
