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
FAKE_SSH_PORTS=""
ssh_listen_ports() { [[ -n "$FAKE_SSH_PORTS" ]] && printf '%s\n' $FAKE_SSH_PORTS; return 0; }
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

# 5. The confirmation tells the operator which port(s) SSH really listens on
#    and to connect the way they normally reach the server. It must not present
#    a guessed `ssh -p <port> user@$(hostname -f)` command: socket activation
#    makes sshd's configured port differ from the listening port, and a NAT may
#    map another external port again.
reset; has_key; ANSWER=n; FAKE_SSH_PORTS="713 2222"; export ANSWER FAKE_SSH_PORTS
run_gate statbus; rc=$?
if [[ $rc -ne 0 ]]; then
    echo "PASS unconfirmed access still refuses"
else
    echo "FAIL unconfirmed access: expected refusal, got rc=$rc"; fail=1
fi
if grep -q 'listening on port(s) 713 2222' <<<"$out"; then
    echo "PASS the prompt names the ports SSH listens on"
else
    echo "FAIL the prompt does not name the listening ports: $out"; fail=1
fi
if grep -q 'the way you normally reach this server' <<<"$out"; then
    echo "PASS the prompt asks for the operator's usual connection details"
else
    echo "FAIL the prompt does not ask for the usual connection details: $out"; fail=1
fi
if grep -Eq 'ssh (-p [0-9]+ )?[^ ]+@example\.test' <<<"$out"; then
    echo "FAIL the prompt still presents a guessed ssh command: $out"; fail=1
else
    echo "PASS the prompt presents no guessed ssh command"
fi
grep -q 'Answering no changes nothing' <<<"$out" || { echo "FAIL the no-op reassurance is missing"; fail=1; }

# 6. populate_authorized_keys merges, so its final line reports what changed,
#    counted before and after, never that the file was replaced.
populate="$(awk '/^populate_authorized_keys\(\)/,/^}$/' "$SCRIPT")"
key_count="$(awk '/^count_authorized_key_bodies\(\)/,/^}$/' "$SCRIPT")"
if [[ -z "$key_count" ]]; then
    echo "FAIL count_authorized_key_bodies is not defined in $SCRIPT"; fail=1
fi
if [[ -z "$populate" ]]; then
    echo "FAIL populate_authorized_keys is not defined in $SCRIPT"; fail=1
else
    keys_work="$(mktemp -d)"
    mkdir -p "$keys_work/bin" "$keys_work/keys" "$keys_work/home/.ssh"
    cat > "$keys_work/bin/getent" <<'FAKE'
#!/usr/bin/env bash
[[ "${1:-}" == "passwd" ]] && echo "statbus:x:1000:1000::${FAKE_HOME}:/bin/bash"
exit 0
FAKE
    cat > "$keys_work/bin/chown" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
    cat > "$keys_work/bin/curl" <<'FAKE'
#!/usr/bin/env bash
url="${!#}"
source="${url#https://github.com/}"
source="${source%.keys}"
file="$KEYS_DIR/$(printf '%s' "$source" | tr '/' '_').keys"
[[ -f "$file" ]] && cat "$file"
FAKE
    chmod +x "$keys_work/bin/"*

    run_populate() { # auth-keys-content fetched-content -> out
        printf '%s\n' "$1" > "$keys_work/home/.ssh/authorized_keys"
        printf '%s\n' "$2" > "$keys_work/keys/alice.keys"
        out="$(FAKE_HOME="$keys_work/home" KEYS_DIR="$keys_work/keys" \
            PATH="$keys_work/bin:$PATH" bash -c '
                log() { echo "[INFO] $*"; }
                log_warn() { echo "[WARN] $*"; }
                log_success() { echo "[OK] $*"; }
                eval "$1"
                populate_authorized_keys statbus alice ""
            ' _ "$key_count
$populate" 2>&1)"
        rc=$?
    }

    run_populate "ssh-ed25519 AAAATESTKEY1 operator@host" "ssh-ed25519 AAAATESTKEY1 alice@example"
    if [[ "$rc" -eq 0 ]] \
        && grep -q 'statbus: 1 key already present, 0 added (1 total in' <<<"$out" \
        && [[ "$(grep -c 'AAAATESTKEY1' "$keys_work/home/.ssh/authorized_keys")" -eq 1 ]] \
        && ! grep -qi 'written' <<<"$out"; then
        echo "PASS a fetched duplicate reports already present, added zero, and stays single"
    else
        echo "FAIL duplicate merge report is wrong (rc=$rc): $out"; fail=1
    fi

    run_populate "ssh-ed25519 AAAAOPERATOR operator@host" "ssh-ed25519 AAAANEWFETCH alice@example"
    if [[ "$rc" -eq 0 ]] \
        && grep -q 'statbus: 1 key already present, 1 added (2 total in' <<<"$out" \
        && grep -q 'AAAAOPERATOR' "$keys_work/home/.ssh/authorized_keys" \
        && grep -q 'AAAANEWFETCH' "$keys_work/home/.ssh/authorized_keys"; then
        echo "PASS a new fetched key is added while the operator key remains"
    else
        echo "FAIL add merge report is wrong (rc=$rc): $out"; fail=1
    fi
    rm -rf "$keys_work"
fi

exit $fail
