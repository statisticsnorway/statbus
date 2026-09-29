#!/usr/bin/env bash
# Offline contract for STATBUS-425 round-3 C3 (found LIVE: run-forks.sh
# v2026.09.3-rc.17 on this branch's backend hit "Invalid instance name ...
# Name must be 1-63 characters long" for 5-install-bool-text-regression and
# 5-install-database-route-interrupted): bootstrap_install_test_vm's shim
# must route on $1's OWN declared identity (statbus-arc-* vs everything
# else), never on whether $2 happens to be empty. INSTALL_VERSION=
# "${INSTALL_VERSION:-}" is an ordinary SCENARIO default (several scenarios
# pass "" as $2 outright), so "$2 empty" wrongly routed real scenario calls
# into the arc branch, which strips a non-matching "statbus-arc-" prefix
# (a no-op) and forks under an oversized name.
#
# This never contacts the LXD host: lxd_fork and _lxd_fork_from_base are
# replaced after sourcing with recorders, matching every other lxd-backend.sh
# offline test's style (lxd-smoke-checkpoint-test.sh, etc).
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
export LXD_CANDIDATE=v2026.09.3-rc.17 LXD_FORK_PREFIX=s2
# shellcheck disable=SC1091
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

calls=()
lxd_fork() { calls+=("lxd_fork|$1|$2"); }
_lxd_fork_from_base() { calls+=("_lxd_fork_from_base|$1|$2|$3"); }

# Case 1: an ordinary scenario call with a NON-EMPTY $2 (the common shape:
# 1-boot-advisory-too-early.sh, 0-happy-upgrade.sh, etc). Must resolve via
# lxd_fork with the statbus-recovery- prefix stripped, exactly as before.
calls=()
bootstrap_install_test_vm statbus-recovery-1-boot-advisory-too-early v2026.09.2
[ "${#calls[@]}" -eq 1 ] || fail "case 1: expected exactly 1 call, got ${#calls[*]}"
[ "${calls[0]}" = "lxd_fork|v2026.09.3-rc.17|1-boot-advisory-too-early" ] || fail "case 1: wrong call: ${calls[0]}"
echo 'PASS: scenario call with a non-empty INSTALL_VERSION resolves via lxd_fork'

# Case 2 (the round-3 regression, reproduced exactly): a scenario call whose
# OWN declared default is INSTALL_VERSION="${INSTALL_VERSION:-}" — a real,
# ordinary scenario default (5-install-bool-text-regression.sh,
# 5-install-stage-b/c/d/e-*.sh), and three scenarios that literally pass ""
# (5-install-database-route-interrupted.sh, 5-install-orphaned-db-volume-
# credentials.sh, 5-install-proxy-never-started.sh). Before this fix, an
# empty $2 unconditionally took the arc branch. Must still resolve via
# lxd_fork, identically to case 1 - the value of $2 must never change which
# branch is taken for a statbus-recovery-* name.
calls=()
bootstrap_install_test_vm statbus-recovery-5-install-bool-text-regression ""
[ "${#calls[@]}" -eq 1 ] || fail "case 2: expected exactly 1 call, got ${#calls[*]}"
[ "${calls[0]}" = "lxd_fork|v2026.09.3-rc.17|5-install-bool-text-regression" ] || fail "case 2: wrong call: ${calls[0]}"
echo 'PASS: scenario call with an EMPTY INSTALL_VERSION (the round-3 regression shape) still resolves via lxd_fork, not the arc branch'

calls=()
bootstrap_install_test_vm statbus-recovery-5-install-database-route-interrupted
[ "${#calls[@]}" -eq 1 ] || fail "case 2b: expected exactly 1 call, got ${#calls[*]}"
[ "${calls[0]}" = "lxd_fork|v2026.09.3-rc.17|5-install-database-route-interrupted" ] || fail "case 2b: wrong call: ${calls[0]}"
echo 'PASS: scenario call with $2 entirely ABSENT still resolves via lxd_fork'

# Case 3: the real arc contract (arc_prepare_box calls
# bootstrap_install_test_vm "$VM_NAME" "" with VM_NAME already statbus-arc-*).
# Must resolve via _lxd_fork_from_base under the hardened-nothing-installed
# base, exactly as the M3a fix intended.
calls=()
bootstrap_install_test_vm statbus-arc-deploy-status-proof ""
[ "${#calls[@]}" -eq 1 ] || fail "case 3: expected exactly 1 call, got ${#calls[*]}"
expected_base="s2-base-v2026-09-3-rc-17-hardened-nothing-installed"
expected_name="s2-v2026-09-3-rc-17-arc-deploy-status-proof"
[ "${calls[0]}" = "_lxd_fork_from_base|$expected_base|$expected_name|hardened-nothing-installed" ] || fail "case 3: wrong call: ${calls[0]}"
echo 'PASS: arc call (statbus-arc-* name, empty $2) resolves via _lxd_fork_from_base under hardened-nothing-installed'

# Case 4: an arc name is never routed through the scenario branch even with
# a non-empty $2 (no real caller does this, but the discriminator must be on
# $1 alone, not a mix of $1-prefix and $2-emptiness).
calls=()
bootstrap_install_test_vm statbus-arc-c-rollback-resurrection some-tag
[ "${#calls[@]}" -eq 1 ] || fail "case 4: expected exactly 1 call, got ${#calls[*]}"
[[ "${calls[0]}" == _lxd_fork_from_base\|* ]] || fail "case 4: arc name with non-empty \$2 must still route via _lxd_fork_from_base: ${calls[0]}"
echo 'PASS: arc call routes via _lxd_fork_from_base regardless of $2'

echo 'PASS: bootstrap_install_test_vm discriminates on $1 (statbus-arc-* vs everything else), never on whether $2 is empty'
