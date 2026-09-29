#!/usr/bin/env bash
# Offline contract for STATBUS-425 round-3 review C2: _lxd_prepare_fresh_answers
# (called by every smoke leg to stage env-config/env-credentials/users.yml onto
# the fleet host before pushing into the guest) must use a HOST staging path
# that is unique PER INVOCATION, never a fixed name. Two smoke legs
# (0-happy-install and 0-happy-upgrade) run as genuinely separate bash
# processes under test-smoke.yaml's max-parallel: 2 and can call this
# function at essentially the same moment; a shared fixed name let a
# concurrent scp truncate-and-rewrite race deliver a partially written
# upload to the wrong guest (review round-3 C2).
#
# This never contacts the LXD host: _lxd_upload/_lxd_push/_lxd_host are
# replaced after sourcing with a recorder. Each invocation is run as a
# genuinely SEPARATE `bash` child process (never `source`d into this test),
# exactly like run-smoke.sh's own scenario-per-process shape (the same
# reason lxd-backend.sh itself pins _LXD_REAL_SSH once per sourcing — see
# its own comment) — this is what makes two invocations' PIDs (and hence
# their staging names, both keyed on $$) genuinely different, not merely
# asserted to be by convention.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lxd-staging-path-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# The probe: sources the REAL lxd-backend.sh, stubs only the three transport
# primitives (_lxd_upload/_lxd_push/_lxd_host), then calls the REAL
# _lxd_prepare_fresh_answers and records every call plus this process's own
# PID (which is what $$ resolves to inside the sourced function, since
# sourcing never forks).
probe="$TMP_ROOT/probe.sh"
cat > "$probe" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
root=$1 log=$2
# shellcheck disable=SC1091
source "$root/test/install-recovery/lib/lxd-backend.sh"
VM_NAME=probe-guest
export VM_NAME
_lxd_upload() { printf 'upload|%s|%s\n' "$1" "$2" >> "$log"; }
_lxd_push() { printf 'push|%s|%s\n' "$1" "$2" >> "$log"; }
_lxd_host() { printf 'host|%s\n' "$*" >> "$log"; }
_lxd_prepare_fresh_answers
printf 'pid|%s\n' "$$" >> "$log"
PROBE

run_probe() {
    local log=$1 github_token=${2:-}
    : > "$log"
    if [ -n "$github_token" ]; then
        GITHUB_TOKEN="$github_token" bash "$probe" "$ROOT" "$log"
    else
        bash "$probe" "$ROOT" "$log"
    fi
}

staged_path() { awk -F'|' -v want="$2" '$1=="push" && $3 ~ want {print $2; exit}' "$1"; }
cleaned() { grep -qF "host|rm -f $2" "$1"; }

log1="$TMP_ROOT/run1.log"
log2="$TMP_ROOT/run2.log"
run_probe "$log1"
run_probe "$log2"

pid1=$(awk -F'|' '$1=="pid"{print $2}' "$log1")
pid2=$(awk -F'|' '$1=="pid"{print $2}' "$log2")
[ -n "$pid1" ] && [ -n "$pid2" ] || fail "probe PID not captured (pid1=$pid1 pid2=$pid2)"
[ "$pid1" != "$pid2" ] || fail "two separate bash child processes reported the SAME PID ($pid1) - test setup is broken, not the fix"

env_staging1=$(staged_path "$log1" 'tmp/env-config$')
env_staging2=$(staged_path "$log2" 'tmp/env-config$')
[ -n "$env_staging1" ] && [ -n "$env_staging2" ] || fail "env-config staging path not recorded (run1=$env_staging1 run2=$env_staging2)"
[ "$env_staging1" != /root/s2-env-config ] || fail "env-config staging path is still the pre-fix fixed name"
[[ "$env_staging1" == "/root/s2-env-config-$pid1" ]] || fail "run1 env-config staging path is not keyed on its own PID: $env_staging1"
[[ "$env_staging2" == "/root/s2-env-config-$pid2" ]] || fail "run2 env-config staging path is not keyed on its own PID: $env_staging2"
[ "$env_staging1" != "$env_staging2" ] || fail "two invocations produced the SAME env-config staging path: $env_staging1"
cleaned "$log1" "$env_staging1" || fail "run1 never removed its env-config staging file from the host: $env_staging1"
cleaned "$log2" "$env_staging2" || fail "run2 never removed its env-config staging file from the host: $env_staging2"
echo 'PASS: env-config staging path is unique per invocation and removed from the host after push'

users_staging1=$(staged_path "$log1" 'tmp/users\.yml$')
users_staging2=$(staged_path "$log2" 'tmp/users\.yml$')
[ -n "$users_staging1" ] && [ -n "$users_staging2" ] || fail "users.yml staging path not recorded (run1=$users_staging1 run2=$users_staging2)"
[ "$users_staging1" != /root/s2-users.yml ] || fail "users.yml staging path is still the pre-fix fixed name"
[[ "$users_staging1" == "/root/s2-users-$pid1.yml" ]] || fail "run1 users.yml staging path is not keyed on its own PID: $users_staging1"
[[ "$users_staging2" == "/root/s2-users-$pid2.yml" ]] || fail "run2 users.yml staging path is not keyed on its own PID: $users_staging2"
[ "$users_staging1" != "$users_staging2" ] || fail "two invocations produced the SAME users.yml staging path: $users_staging1"
cleaned "$log1" "$users_staging1" || fail "run1 never removed its users.yml staging file from the host: $users_staging1"
cleaned "$log2" "$users_staging2" || fail "run2 never removed its users.yml staging file from the host: $users_staging2"
echo 'PASS: users.yml staging path is unique per invocation and removed from the host after push'

# GITHUB_TOKEN branch: only taken when the variable is set (recovery arcs
# only, per _lxd_prepare_fresh_answers's own comment) - exercise it
# explicitly rather than relying on the two unconditional runs above.
log3="$TMP_ROOT/run3.log"
run_probe "$log3" 'fake-token-for-offline-test'
pid3=$(awk -F'|' '$1=="pid"{print $2}' "$log3")
[ -n "$pid3" ] || fail "run3 (GITHUB_TOKEN set) probe PID not captured"
cred_staging3=$(staged_path "$log3" 'tmp/env-credentials$')
[ -n "$cred_staging3" ] || fail "env-credentials staging path not recorded when GITHUB_TOKEN is set"
[ "$cred_staging3" != /root/s2-env-credentials ] || fail "env-credentials staging path is still the pre-fix fixed name"
[[ "$cred_staging3" == "/root/s2-env-credentials-$pid3" ]] || fail "run3 env-credentials staging path is not keyed on its own PID: $cred_staging3"
cleaned "$log3" "$cred_staging3" || fail "run3 never removed its env-credentials staging file from the host (S1): $cred_staging3"
grep -qF "host|lxc exec probe-guest -- chmod 0600 /tmp/env-credentials" "$log3" || fail "env-credentials permissions were not tightened on the guest"
echo 'PASS: env-credentials staging path is unique per invocation, removed from the host after push, and never left with a fixed name (S1)'
