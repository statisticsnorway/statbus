#!/usr/bin/env bash
# STATBUS-501: cloud configuration must not be applied to a standalone
# installation, and cloud-only work must not even be VISIBLE to one. The
# deploy-key source, its fetch, the devops account and the CI command allowlist
# exist to serve OUR cloud and CI model, so they happen only when cloud intent is
# declared (--cloud / CLOUD=true) - and without it the stages are not part of the
# run at all: no header, no prompt, no explanation of how to enable them.
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

# 1. Behaviour: the gate itself, for the three states of cloud intent.
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

# 2. Contract: every fetch goes through that one gate.
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

# 3. Contract: a standalone run must not have to carry the variable at all. A
#    full run requires exactly these keys, read from the stage table.
required="$(bash -c 'source "$1"; required_env_vars | paste -sd " " -' _ "$SCRIPT" 2>/dev/null)"
if [[ "$required" == "ADMIN_EMAIL EXTRA_LOCALES GITHUB_USERS SERVICE_USER" ]]; then
    echo "PASS a full run requires ADMIN_EMAIL EXTRA_LOCALES GITHUB_USERS SERVICE_USER, not GITHUB_DEPLOY_KEYS"
else
    echo "FAIL a full run requires '$required'"; fail=1
fi

# 4. Contract: a cloud-only stage is INVISIBLE without cloud intent. The gate
#    precedes the stage header, so nothing is printed at all, and the gate itself
#    is silent. Announcing the stage and explaining how to enable it would tell a
#    customer about our support access model - the leak this ticket is about.
gate_is_invisible() {
    local fn="$1" label="$2" text gate header body start
    text="$(awk "/^${fn}\\(\\)/,/^}$/" "$SCRIPT")"
    gate="$(grep -n 'CLOUD:-false' <<<"$text" | head -1 | cut -d: -f1)"
    header="$(grep -n 'stage_header ' <<<"$text" | head -1 | cut -d: -f1)"
    if [[ -n "$gate" && -n "$header" && "$gate" -lt "$header" ]]; then
        echo "PASS $label: the gate precedes the header"
    else
        echo "FAIL $label: gate=${gate:-missing} header=${header:-missing}"; fail=1
    fi
    start="${gate:-1}"
    body="$(sed -n "${start},$(( start + 3 ))p" <<<"$text")"
    if grep -Eq '(^|[[:space:]])(log|log_warn|log_error|log_header|echo)[[:space:]]' <<<"$body"; then
        echo "FAIL $label: the gate prints something before returning"; fail=1
    else
        echo "PASS $label: the gate says nothing"
    fi
}

gate_is_invisible stage_user_setup "user-setup (devops) is invisible without cloud intent"
gate_is_invisible stage_ci_allowlist "ci-allowlist is invisible without cloud intent"

# 5. Stage 7 runs on a standalone box too, but its CI deploy-key wording is
#    cloud-only. Run the real stage with a refusing prompt so it prints its
#    introduction and returns before changing anything.
stage7="$(awk '/^stage_service_account\(\)/,/^}$/' "$SCRIPT")"
if [[ -z "$stage7" ]]; then
    echo "FAIL stage_service_account is not defined in $SCRIPT"; fail=1
else
    stage7_text() { # cloud -> intro output
        CLOUD="$1" SERVICE_USER="statbus" GITHUB_USERS="alice" \
        GITHUB_DEPLOY_KEYS="acme/statbus" bash -c '
            stage_header() { :; }
            log() { :; }
            log_warn() { echo "WARN $*"; }
            ask_yes_no() { return 1; }
            record_stage() { :; }
            deploy_keys_for_this_run() {
                [[ "${CLOUD:-false}" == "true" ]] && printf "%s" "$GITHUB_DEPLOY_KEYS"
            }
            eval "$1"
            stage_service_account
        ' _ "$stage7" 2>&1
    }

    standalone7="$(stage7_text false)"
    cloud7="$(stage7_text true)"
    echo "--- standalone Stage 7 intro ---"; echo "$standalone7"; echo "-------------------------------"
    echo "--- cloud Stage 7 intro ---"; echo "$cloud7"; echo "--------------------------"

    if grep -q "Operators SSH as 'statbus' to install and operate StatBus." <<<"$standalone7"; then
        echo "PASS standalone Stage 7 tells operators they sign in as statbus"
    else
        echo "FAIL standalone Stage 7 does not tell operators they sign in as statbus"; fail=1
    fi
    if grep -qiE 'CI deploy|Deploy keys' <<<"$standalone7"; then
        echo "FAIL standalone Stage 7 still shows CI deploy-key wording"; fail=1
    else
        echo "PASS standalone Stage 7 shows no CI deploy-key wording"
    fi
    if grep -q 'CI deploy workflows' <<<"$cloud7" \
        && grep -q 'Deploy keys: acme/statbus' <<<"$cloud7" \
        && grep -q 'repo deploy key is required' <<<"$cloud7"; then
        echo "PASS cloud Stage 7 keeps the CI/deploy-key wording"
    else
        echo "FAIL cloud Stage 7 lost the CI/deploy-key wording"; fail=1
    fi
fi

exit $fail
