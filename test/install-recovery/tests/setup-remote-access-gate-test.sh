#!/usr/bin/env bash
# STATBUS-495: the SSH stage must establish and CONFIRM remote access before it
# disables password authentication. Four behaviours, and nothing here touches a
# real home directory or a real SSH service.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail (that copy
# has no access gate), which is how the red half of the evidence is produced.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

gate="$(awk '/^ensure_remote_access\(\)/,/^}/' "$SCRIPT")"
if [[ -z "$gate" ]]; then
    echo "FAIL ensure_remote_access is not defined in $SCRIPT"
    exit 1
fi

# The access gate calls deploy_keys_for_this_run(), so this test needs that
# function too: without it the gate runs against an undefined command and the
# deploy-key argument is empty for the wrong reason (STATBUS-501).
deploy_helper="$(awk '/^deploy_keys_for_this_run\(\)/,/^}/' "$SCRIPT")"
if [[ -z "$deploy_helper" ]]; then
    echo "FAIL deploy_keys_for_this_run is not defined in $SCRIPT"
    exit 1
fi

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export FAKE_HOME="$sandbox/home"
mkdir -p "$FAKE_HOME/.ssh"

# Stubs: the gate must be exercised without a real account, a real hostname, or
# a real GitHub fetch.
remote_access_home() { echo "$FAKE_HOME"; }
hostname() { echo "example.test"; }
log() { echo "[INFO] $*"; }
log_success() { echo "[OK] $*"; }
log_error() { echo "[ERROR] $*"; }
POPULATED=""; PROMPTED=""
populate_authorized_keys() { POPULATED="$1 $2 $3"; return "${POPULATE_RC:-0}"; }
ask_yes_no() { PROMPTED="$1 default=$2"; [[ "${ANSWER:-n}" == "y" ]]; }

eval "$gate"
eval "$deploy_helper"

reset() { POPULATED=""; PROMPTED=""; rm -f "$FAKE_HOME/.ssh/authorized_keys"; }
has_key() { printf 'ssh-ed25519 AAAATESTKEY test@example\n' > "$FAKE_HOME/.ssh/authorized_keys"; }

# Run the gate in THIS shell: a command substitution would run it in a subshell
# and the stubs' side effects would never reach these assertions.
run_gate() {
    ensure_remote_access "$@" > "$sandbox/gate.out" 2>&1
    local rc=$?
    out="$(cat "$sandbox/gate.out")"
    return $rc
}

# 1. Keys already present: nothing is installed, and answering no changes nothing.
reset; has_key; ANSWER=n; export ANSWER
run_gate statbus; rc=$?
if [[ $rc -ne 0 && -z "$POPULATED" && -n "$PROMPTED" ]]; then
    echo "PASS existing keys are recognised and 'no' refuses (nothing installed, prompt shown)"
else
    echo "FAIL existing-keys/no: rc=$rc populated='$POPULATED' prompted='$PROMPTED'"; fail=1
fi
grep -q 'already set up' <<<"$out" || { echo "FAIL the operator is not told access already exists"; fail=1; }

# 2. Keys already present and confirmed: proceeds without installing anything.
reset; has_key; ANSWER=y; export ANSWER
run_gate statbus; rc=$?
if [[ $rc -eq 0 && -z "$POPULATED" ]]; then
    echo "PASS confirmed existing access proceeds and installs nothing"
else
    echo "FAIL existing-keys/yes: rc=$rc populated='$POPULATED'"; fail=1
fi

# 3. No keys but GITHUB_USERS names someone: installs, then confirms. With NO
#    cloud intent the deploy-key argument is empty by design (STATBUS-501).
reset; ANSWER=y; export ANSWER GITHUB_USERS="alice" GITHUB_DEPLOY_KEYS="statisticsnorway/statbus"
unset CLOUD
run_gate statbus; rc=$?
if [[ $rc -eq 0 && "$POPULATED" == "statbus alice " ]]; then
    echo "PASS a standalone run installs the operator's keys and no deploy keys"
else
    echo "FAIL install-from-GITHUB_USERS: rc=$rc populated='$POPULATED'"; fail=1
fi

# 3c. The same call WITH cloud intent passes the deploy keys through.
reset; ANSWER=y; export ANSWER GITHUB_USERS="alice" GITHUB_DEPLOY_KEYS="statisticsnorway/statbus" CLOUD=true
run_gate statbus; rc=$?
if [[ $rc -eq 0 && "$POPULATED" == "statbus alice statisticsnorway/statbus" ]]; then
    echo "PASS a cloud run installs the deploy keys as well"
else
    echo "FAIL cloud install-from-GITHUB_USERS: rc=$rc populated='$POPULATED'"; fail=1
fi
unset CLOUD

# 3b. The installation failing must refuse, not continue to the prompt.
reset; ANSWER=y; export ANSWER POPULATE_RC=1
run_gate statbus; rc=$?
if [[ $rc -ne 0 && -z "$PROMPTED" ]]; then
    echo "PASS a failed key installation refuses before asking anything"
else
    echo "FAIL failed-install: rc=$rc prompted='$PROMPTED'"; fail=1
fi
unset POPULATE_RC

# 4. No keys and no GITHUB_USERS: refuse, name the configuration entry, and never prompt.
reset; ANSWER=y; export ANSWER GITHUB_USERS=""
run_gate statbus; rc=$?
if [[ $rc -ne 0 && -z "$PROMPTED" && -z "$POPULATED" ]]; then
    echo "PASS no keys and no GITHUB_USERS refuses without prompting"
else
    echo "FAIL no-keys-no-users: rc=$rc prompted='$PROMPTED' populated='$POPULATED'"; fail=1
fi
grep -q 'GITHUB_USERS' <<<"$out" || { echo "FAIL the refusal does not name GITHUB_USERS"; fail=1; }

exit $fail
