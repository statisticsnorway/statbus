#!/usr/bin/env bash
# STATBUS-556: the test fleet hardens ONE base per candidate with the full
# setup an operator runs, and every installed base is a copy of that hardened
# snapshot plus its install.
#
# SYNTHETIC: a fake LXD store (tests/fake-lxc.sh), not a real guest. Runs the
# REAL lxd_base_for_candidate and records every host command, then asserts:
#  1. the hardened base runs setup once, with no stage selection at all;
#  2. an installed base is created by copying hardened-nothing-installed's
#     checkpoint and runs no setup of its own;
#  3. no harness file hands setup a stage selection.
#
# Point HARNESS_LIB_DIR at an older lib/ to see this fail (the red half).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
LIB=${HARNESS_LIB_DIR:-$ROOT/test/install-recovery/lib}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0
pass() { echo "PASS $*"; }
nope() { echo "FAIL $*"; fail=1; }

export LXD_CANDIDATE=v2099.01.1-rc.1 LXD_FORK_PREFIX=s2 LXD_LOG_DIR=$TMP LXD_STAGE_ID=t HARNESS_ROOT=$ROOT
# shellcheck disable=SC1090,SC1091
source "$LIB/lxd-backend.sh"
# shellcheck disable=SC1091
source "$ROOT/test/install-recovery/tests/fake-lxc.sh"
mk_fake_env "$TMP/env"; S=$FAKE_STORE
CMDS=$TMP/cmds; : > "$CMDS"
_lxd_mark() { :; }
_lxd_upload() { :; }; _lxd_push() { :; }
_lxd_ready() { return 0; }
lxd_certificates() { return 0; }
lxd_capture_failure() { :; }
# Every host command is recorded; lxc launch/copy/snapshot change the store.
_lxd_host() {
    printf '%s\n' "$*" >> "$CMDS"
    case "$1 $2" in
        "lxc launch") mkdir -p "$S/$4"; printf 26.04 > "$S/$4/image.version"; return 0 ;;
        "lxc exec") return 0 ;;
    esac
    "$@"
}
hard=$(_lxd_name "$LXD_CANDIDATE-hardened-nothing-installed")
inst_cp=installed-v2099.01.0-standalone-pre
inst=$(_lxd_name "$LXD_CANDIDATE-$inst_cp")

# 1. The hardened base: one launch, one full setup.
lxd_base_for_candidate "$LXD_CANDIDATE" hardened-nothing-installed >/dev/null 2>&1 || nope "hardened base build failed"
setups=$(grep -c "setup.sh" "$CMDS" || true)
if grep "setup.sh" "$CMDS" | grep -qE -- '--(skip|only)-stages|SKIP_STAGES|ONLY_STAGES'; then
    nope "the hardened base runs setup with a stage selection: $(grep setup.sh "$CMDS" | head -1)"
elif [ "$setups" = 1 ]; then
    pass "the hardened base runs the full setup once, no stage left out"
else
    nope "the hardened base ran setup $setups times"
fi
[ -e "$S/$hard/snap" ] && pass "the hardened base is snapshotted" || nope "the hardened base has no checkpoint"

# 2. An installed base copies that checkpoint and runs no setup.
: > "$CMDS"
lxd_base_for_candidate "$LXD_CANDIDATE" "$inst_cp" >/dev/null 2>&1 || true
if grep -qx "lxc copy $hard/checkpoint $inst.*" "$CMDS" || grep -q "^lxc copy $hard/checkpoint $inst" "$CMDS"; then
    pass "the installed base is a copy of the hardened checkpoint"
else
    nope "the installed base is not copied from $hard/checkpoint; host commands: $(grep -E '^lxc (launch|copy)' "$CMDS" | paste -sd ';' -)"
fi
if grep -q "setup.sh" "$CMDS"; then
    nope "the installed base runs setup itself"
else
    pass "the installed base runs no setup of its own"
fi

# 3. No harness file selects setup stages.
hits=$(grep -nE -- '--(skip|only)-stages|SKIP_STAGES|ONLY_STAGES' \
    "$LIB/lxd-backend.sh" "$LIB/vm-bootstrap.sh" "$ROOT/ops/lxd-fleet/base.sh" \
    "$ROOT"/test/install-recovery/scenarios/*.sh 2>/dev/null || true)
if [ -z "$hits" ]; then
    pass "no harness file selects setup stages"
else
    nope "harness files select setup stages:"; sed 's/^/    /' <<<"$hits"
fi
exit $fail
