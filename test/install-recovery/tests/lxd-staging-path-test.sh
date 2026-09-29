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
printf 'pid|%s\n' "$LXD_STAGE_ID" >> "$log"
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
[ "$pid1" != "$pid2" ] || fail "two separate invocations got the SAME stage id ($pid1)"

env_staging1=$(staged_path "$log1" 'tmp/env-config$')
env_staging2=$(staged_path "$log2" 'tmp/env-config$')
[ -n "$env_staging1" ] && [ -n "$env_staging2" ] || fail "env-config staging path not recorded (run1=$env_staging1 run2=$env_staging2)"
[ "$env_staging1" != /root/s2-env-config ] || fail "env-config staging path is still the pre-fix fixed name"
[[ "$env_staging1" == "/root/s2-env-config-$pid1" ]] || fail "run1 env-config staging path is not keyed on its own stage id: $env_staging1"
[[ "$env_staging2" == "/root/s2-env-config-$pid2" ]] || fail "run2 env-config staging path is not keyed on its own stage id: $env_staging2"
[ "$env_staging1" != "$env_staging2" ] || fail "two invocations produced the SAME env-config staging path: $env_staging1"
cleaned "$log1" "$env_staging1" || fail "run1 never removed its env-config staging file from the host: $env_staging1"
cleaned "$log2" "$env_staging2" || fail "run2 never removed its env-config staging file from the host: $env_staging2"
echo 'PASS: env-config staging path is unique per invocation and removed from the host after push'

users_staging1=$(staged_path "$log1" 'tmp/users\.yml$')
users_staging2=$(staged_path "$log2" 'tmp/users\.yml$')
[ -n "$users_staging1" ] && [ -n "$users_staging2" ] || fail "users.yml staging path not recorded (run1=$users_staging1 run2=$users_staging2)"
[ "$users_staging1" != /root/s2-users.yml ] || fail "users.yml staging path is still the pre-fix fixed name"
[[ "$users_staging1" == "/root/s2-users-$pid1.yml" ]] || fail "run1 users.yml staging path is not keyed on its own stage id: $users_staging1"
[[ "$users_staging2" == "/root/s2-users-$pid2.yml" ]] || fail "run2 users.yml staging path is not keyed on its own stage id: $users_staging2"
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
[[ "$cred_staging3" == "/root/s2-env-credentials-$pid3" ]] || fail "run3 env-credentials staging path is not keyed on its own stage id: $cred_staging3"
cleaned "$log3" "$cred_staging3" || fail "run3 never removed its env-credentials staging file from the host (S1): $cred_staging3"
grep -qF "host|lxc exec probe-guest -- chmod 0600 /tmp/env-credentials" "$log3" || fail "env-credentials permissions were not tightened on the guest"
echo 'PASS: env-credentials staging path is unique per invocation, removed from the host after push, and never left with a fixed name (S1)'

# Review round-4 R4-1: the two smoke legs run on SEPARATE runners, where the
# PID can coincide. Two invocations with the SAME PID but different GitHub
# jobs must still get different staging names. Simulate with a fixed PID by
# giving both runs the same run id/attempt and differing only in GITHUB_JOB,
# then check the ids differ in the job component AND in their random part
# (even if the job name were equal, the random part separates them).
job_id() { GITHUB_RUN_ID=77 GITHUB_RUN_ATTEMPT=1 GITHUB_JOB="$1" bash -c 'source "$0/test/install-recovery/lib/lxd-backend.sh"; printf %s "$LXD_STAGE_ID"' "$ROOT"; }
idA=$(job_id smoke-install)
idB=$(job_id smoke-upgrade)
idC=$(job_id smoke-install)
[ "$idA" != "$idB" ] || fail "different jobs got the same stage id: $idA"
[ "$idA" != "$idC" ] || fail "two runs of the same job got the same stage id (no per-run randomness): $idA"
case "$idA" in 77-1-smoke-install-*) ;; *) fail "stage id does not carry run/attempt/job: $idA" ;; esac
echo 'PASS: staging id is unique per job and per run, not merely per PID (R4-1)'

# Review round-4 R4-2: the base builder stages the 75 KB setup.sh on the host
# (the round-3 C2 race site). Drive the REAL _lxd_build_base_for_candidate for a
# hardened-nothing-installed base with the transport stubbed: the setup.sh
# staging name must carry this invocation's stage id and be removed after push.
base_probe="$TMP_ROOT/base-probe.sh"
cat > "$base_probe" <<'PROBE'
#!/usr/bin/env bash
set -uo pipefail
root=$1 log=$2
# shellcheck disable=SC1091
source "$root/test/install-recovery/lib/lxd-backend.sh"
_lxd_upload() { printf 'upload|%s|%s\n' "$1" "$2" >> "$log"; }
_lxd_push() { printf 'push|%s|%s\n' "$1" "$2" >> "$log"; }
_lxd_host() {
    printf 'host|%s\n' "$*" >> "$log"
    case "$*" in
        "lxc info "*) return 1 ;;                          # base does not exist yet
        *"snapshot"*"checkpoint"*|*"lxc info"*"/checkpoint"*) return 1 ;;
    esac
    return 0
}
lxd_certificates() { :; }
_lxd_mark() { :; }
_lxd_build_base_for_candidate v2026.09.3-rc.99 hardened-nothing-installed >/dev/null 2>&1 || true
printf 'id|%s\n' "$LXD_STAGE_ID" >> "$log"
PROBE
blog="$TMP_ROOT/base.log"; : > "$blog"
bash "$base_probe" "$ROOT" "$blog"
bid=$(awk -F'|' '$1=="id"{print $2}' "$blog")
setup_staging=$(awk -F'|' '$1=="push" && $3 ~ /root\/setup\.sh$/ {print $2; exit}' "$blog")
[ -n "$setup_staging" ] || fail "base builder never pushed setup.sh (probe log: $(tr '\n' ' ' < "$blog" | cut -c1-300))"
[ "$setup_staging" != /root/s2-setup.sh ] || fail "setup.sh staging path is still the fixed name"
[[ "$setup_staging" == "/root/s2-setup-$bid.sh" ]] || fail "setup.sh staging path is not keyed on the stage id: $setup_staging"
cleaned "$blog" "$setup_staging" || fail "base builder never removed its setup.sh staging file: $setup_staging"
echo 'PASS: base builder stages setup.sh under the per-job id and removes it (R4-2)'
