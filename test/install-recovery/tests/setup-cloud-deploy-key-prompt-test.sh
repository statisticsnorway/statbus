#!/usr/bin/env bash
# STATBUS-491: the CI deploy-key question belongs to a cloud installation.
# A plain standalone preparation must not ask it; with --cloud (or CLOUD=true)
# it is asked and its answer is saved, so every answer possible before remains
# possible with the flag.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

run_setup() { # $1=CLOUD value, $2=home dir, stdin=answers
    mkdir -p "$2"
    HOME="$2" SUDO_USER= CLOUD="$1" bash -c '
        source "$1"
        ENV_FILE="$HOME/.setup-ubuntu.env"
        setup_env
        echo "SAVED: $(grep ^GITHUB_DEPLOY_KEYS= "$ENV_FILE")"
    ' _ "$SCRIPT" 2>&1
}

standalone="$(printf '\nalice\n\n\n\n' | run_setup false "$work/standalone")"
echo "--- standalone transcript ---"; echo "$standalone"
if grep -qi 'deploy-key' <<<"$standalone"; then
    echo "FAIL standalone preparation asks the deploy-key/CI question"; fail=1
else
    echo "PASS standalone preparation does not ask the deploy-key/CI question"
fi

cloud="$(printf '\nalice\nacme/ci\n\n\n' | run_setup true "$work/cloud")"
echo "--- cloud transcript ---"; echo "$cloud"
if grep -qi 'deploy-key' <<<"$cloud" && grep -q 'SAVED: GITHUB_DEPLOY_KEYS="acme/ci"' <<<"$cloud"; then
    echo "PASS cloud preparation asks the deploy-key question and saves the answer"
else
    echo "FAIL cloud preparation did not ask/save the deploy-key answer"; fail=1
fi

help="$(bash "$SCRIPT" --help 2>&1)"
if grep -q -- '--cloud' <<<"$help" && grep -q -- '--cloud' "$ROOT/doc/setup-ubuntu-lts.md"; then
    echo "PASS --cloud is documented in --help and doc/setup-ubuntu-lts.md"
else
    echo "FAIL --cloud is not documented in --help and doc/setup-ubuntu-lts.md"; fail=1
fi
exit $fail
