#!/usr/bin/env bash
# STATBUS-501: cloud configuration must not be applied to a standalone
# installation. The deploy-key source, its fetch and the devops account exist to
# serve OUR cloud and CI model, so they must happen only when cloud intent is
# declared (--cloud / CLOUD=true), and no call site may install our CI keys on a
# box that is not ours.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail, which makes
# the red half of the evidence.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

helper="$(awk '/^deploy_keys_for_this_run\(\)/,/^}$/' "$SCRIPT")"
if [[ -z "$helper" ]]; then
    echo "FAIL deploy_keys_for_this_run is not defined in $SCRIPT"
    exit 1
fi
eval "$helper"

present() { if [[ -n "$2" ]]; then echo "PASS $1"; else echo "FAIL $1 (not found)"; fail=1; fi; }

# 1. Behaviour: the gate itself, exercised for the three states of cloud intent.
GITHUB_DEPLOY_KEYS="statisticsnorway/statbus"
unset CLOUD
got="$(deploy_keys_for_this_run)"
if [[ -z "$got" ]]; then
    echo "PASS no cloud intent installs no deploy keys"
else
    echo "FAIL no cloud intent still installs '$got'"; fail=1
fi

CLOUD=false
got="$(deploy_keys_for_this_run)"
if [[ -z "$got" ]]; then
    echo "PASS CLOUD=false installs no deploy keys"
else
    echo "FAIL CLOUD=false still installs '$got'"; fail=1
fi

CLOUD=true
got="$(deploy_keys_for_this_run)"
if [[ "$got" == "statisticsnorway/statbus" ]]; then
    echo "PASS cloud intent installs the configured deploy keys"
else
    echo "FAIL cloud intent lost the deploy keys (got '$got')"; fail=1
fi

# 2. Contract: every fetch goes through that one gate, so no call site can use
#    the raw variable on a standalone box.
raw_sites="$(grep -c 'populate_authorized_keys .*"\$GITHUB_DEPLOY_KEYS"' "$SCRIPT" || true)"
if [[ "$raw_sites" == "0" ]]; then
    echo "PASS no call site passes the raw deploy-key variable"
else
    echo "FAIL $raw_sites call site(s) bypass the cloud gate"; fail=1
fi
gated_sites="$(grep -c 'populate_authorized_keys .*deploy_keys_for_this_run' "$SCRIPT" || true)"
if [[ "$gated_sites" -ge 3 ]]; then
    echo "PASS all $gated_sites fetch sites use the gate"
else
    echo "FAIL only $gated_sites fetch site(s) use the gate"; fail=1
fi

# 3. Contract: a standalone run must not have to carry the variable at all.
if grep -Eq '\[7\]="[^"]*GITHUB_DEPLOY_KEYS' "$SCRIPT"; then
    echo "FAIL stage 7 still declares GITHUB_DEPLOY_KEYS as required"; fail=1
else
    echo "PASS stage 7 does not require GITHUB_DEPLOY_KEYS"
fi

# 4. Contract: the devops stage is skipped without cloud intent.
present "the devops stage is gated on cloud intent" "$(grep -n 'Stage 6 is cloud-only' <<<"$(sed -n '/^stage_user_setup()/,/^}$/p' "$SCRIPT")")"

exit $fail
