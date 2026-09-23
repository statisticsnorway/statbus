#!/bin/bash
# STATBUS-370: drive the real harness long-runner, failure capture, keep branch,
# and reaper through a localhost sshd. No cloud or product containers are used.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-harness-selftest.XXXXXX")
SSHD_PID=""
REMOTE_STATE=/var/tmp/statbus-harness
REMOTE_STATE_OWNED=0
cleanup() {
    [ -z "$SSHD_PID" ] || kill "$SSHD_PID" 2>/dev/null || true
    rm -rf "$TMP_ROOT"
    if [ "$REMOTE_STATE_OWNED" = 1 ] && [ -f "$REMOTE_STATE/.statbus-selftest-$$" ]; then
        rm -rf "$REMOTE_STATE"
    fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
for command_name in sshd ssh-keygen ssh scp tmux timeout; do
    command -v "$command_name" >/dev/null || fail "$command_name is required"
done

mkdir -p "$TMP_ROOT/home/.ssh" "$TMP_ROOT/bin"
chmod 700 "$TMP_ROOT/home/.ssh"
ssh-keygen -q -t ed25519 -N '' -f "$TMP_ROOT/client" </dev/null
ssh-keygen -q -t ed25519 -N '' -f "$TMP_ROOT/host" </dev/null
cp "$TMP_ROOT/client.pub" "$TMP_ROOT/home/.ssh/authorized_keys"
chmod 600 "$TMP_ROOT/home/.ssh/authorized_keys"
PORT=$((42000 + ($$ % 2000)))
USER_NAME=$(id -un)
cat > "$TMP_ROOT/sshd_config" <<EOF
ListenAddress 127.0.0.1
Port $PORT
HostKey $TMP_ROOT/host
PidFile $TMP_ROOT/sshd.pid
AuthorizedKeysFile $TMP_ROOT/home/.ssh/authorized_keys
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM no
PermitRootLogin no
AllowUsers $USER_NAME
LogLevel ERROR
EOF
"$(command -v sshd)" -D -e -f "$TMP_ROOT/sshd_config" >"$TMP_ROOT/sshd.log" 2>&1 &
SSHD_PID=$!
BASE_SSH_OPTS=(-i "$TMP_ROOT/client" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
for _ in $(seq 1 50); do
    ssh "${BASE_SSH_OPTS[@]}" "$USER_NAME@127.0.0.1" true 2>/dev/null && break
    sleep 0.1
done
ssh "${BASE_SSH_OPTS[@]}" "$USER_NAME@127.0.0.1" true 2>/dev/null || { cat "$TMP_ROOT/sshd.log" >&2; fail "localhost sshd did not become ready"; }
[ ! -e "$REMOTE_STATE" ] || fail "$REMOTE_STATE already exists; refusing to disturb another harness run"
mkdir -p "$REMOTE_STATE"
touch "$REMOTE_STATE/.statbus-selftest-$$"
REMOTE_STATE_OWNED=1

REAL_SSH=$(command -v ssh)
REAL_SCP=$(command -v scp)
REAL_TMUX=$(command -v tmux)
cat > "$TMP_ROOT/bin/ssh" <<'EOF'
#!/bin/bash
set -euo pipefail
args=("$@")
for i in "${!args[@]}"; do
    if [[ "${args[$i]}" == root@127.0.0.1 ]]; then
        args[$i]="${SELFTEST_USER:?}@127.0.0.1"
    fi
    if [[ "${args[$i]}" == *'sudo -u statbus tmux new-session'* ]]; then
        args[$i]="${args[$i]//sudo -u statbus /}"
        args[$i]="${args[$i]//tmux new-session/${REAL_TMUX:?} new-session}"
    fi
done
exec "${REAL_SSH:?}" "${args[@]}"
EOF
cat > "$TMP_ROOT/bin/scp" <<'EOF'
#!/bin/bash
set -euo pipefail
args=("$@")
for i in "${!args[@]}"; do
    args[$i]="${args[$i]//root@127.0.0.1:/${SELFTEST_USER:?}@127.0.0.1:}"
    if [[ "${args[$i]}" == -p ]] && [[ "${args[$((i + 1))]:-}" =~ ^[0-9]+$ ]]; then
        args[$i]=-P
    fi
done
printf 'scp %s\n' "${args[*]}" >> "${EVENTS:?}"
exec "${REAL_SCP:?}" "${args[@]}"
EOF
cat > "$TMP_ROOT/bin/hcloud" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'hcloud %s\n' "$*" >> "${EVENTS:?}"
case "$*" in
    'server ip '*) printf '127.0.0.1\n' ;;
    'server delete '*) ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$TMP_ROOT/bin/ssh" "$TMP_ROOT/bin/scp" "$TMP_ROOT/bin/hcloud"
export REAL_SSH REAL_SCP REAL_TMUX SELFTEST_USER="$USER_NAME"

prepare_fixture() {
    local name="$1"
    local fixture="$TMP_ROOT/$name"
    mkdir -p "$fixture/test/install-recovery/lib" "$fixture/tmp"
    cp "$ROOT/test/install-recovery/lib/vm-bootstrap.sh" "$fixture/test/install-recovery/lib/"
    cp "$ROOT/test/install-recovery/lib/watch-decisions.sh" "$fixture/test/install-recovery/lib/"
    printf '%s\n' "$fixture"
}

run_contract() (
    set +e
    local fixture="$1" keep="$2" fixture_label="$3"
    local vm_name="statbus-recovery-selftest-$fixture_label"
    local out="$fixture/contract.out"
    export HCLOUD_TOKEN=selftest EVENTS="$fixture/events"
    export PATH="$TMP_ROOT/bin:$PATH"
    : > "$EVENTS"
    # shellcheck disable=SC1090
    source "$fixture/test/install-recovery/lib/vm-bootstrap.sh"
    SSH_OPTS=(-i "$TMP_ROOT/client" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
    VM_IP=127.0.0.1
    VM_OWNED_BY_THIS_RUN=1
    KEEP_VM="$keep"
    KEEP_VM_ON_FAILURE=0
    LONG_CMD_MAX_MIN=1
    LONG_CMD_POLL_SECS=1
    LONG_CMD_NO_PROGRESS_SECS=20
    VM_EXEC() { ssh "${SSH_OPTS[@]}" "$USER_NAME@127.0.0.1" "$@"; }

    find "$REMOTE_STATE" -mindepth 1 ! -name ".statbus-selftest-$$" -exec rm -rf -- {} +
    local expected="$fixture/expected.log"
    for n in $(seq -w 1 40); do printf 'failure-evidence-line-%s\n' "$n"; done > "$expected"

    {
        _run_long_via_tmux 127.0.0.1 "stage-$fixture_label" \
            "cat '$expected'; exit 1" "$vm_name"
        stage_rc=$?
        printf 'fixture stage exit=%s\n' "$stage_rc"
        cleanup_vm "$vm_name" "$stage_rc"
    } > "$out" 2>&1

    local captured="$fixture/tmp/$vm_name/registered/stage-$fixture_label--stage-$fixture_label.log"
    [ "${stage_rc:-0}" -eq 1 ] || { echo "contract: stage rc was ${stage_rc:-unset}" >&2; return 1; }
    grep -Fq "FAILURE CLASS: remote-stage-failed[stage-$fixture_label] exit=1" "$out" || { echo "contract: real long-runner diagnostic missing" >&2; return 1; }
    for n in $(seq -w 11 40); do
        grep -q "failure-evidence-line-$n" "$out" || { echo "contract: output omitted line $n" >&2; return 1; }
    done
    cmp -s "$expected" "$captured" || { echo "contract: registered log was not captured byte-identical" >&2; return 1; }
    grep -q "captured  stage-$fixture_label" "$out" || { echo "contract: real capture index missing" >&2; return 1; }

    local scp_line delete_line
    scp_line=$(grep -n '^scp ' "$EVENTS" | tail -1 | cut -d: -f1 || true)
    delete_line=$(grep -n "^hcloud server delete $vm_name$" "$EVENTS" | cut -d: -f1 || true)
    if [ "$keep" = 1 ]; then
        [ -z "$delete_line" ] || { echo "contract: KEEP_VM deleted the box" >&2; return 1; }
        grep -q 'KEEP_VM=1.*leaving' "$out" || { echo "contract: KEEP_VM diagnostic missing" >&2; return 1; }
    else
        [ -n "$scp_line" ] && [ -n "$delete_line" ] && [ "$scp_line" -lt "$delete_line" ] || {
            echo "contract: real reaper did not run after the last scp" >&2
            return 1
        }
    fi
)

healthy=$(prepare_fixture healthy)
run_contract "$healthy" 0 delete || { cat "$healthy/contract.out" >&2; fail "real capture-before-delete contract failed"; }
run_contract "$healthy" 1 keep || { cat "$healthy/contract.out" >&2; fail "real KEEP_VM contract failed"; }

mutated=$(prepare_fixture mutated)
python3 - "$mutated/test/install-recovery/lib/vm-bootstrap.sh" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = 'if ! scp -O -r "${SSH_OPTS[@]}" "root@$ip:$remote_dir/*" "$out_dir/"; then'
new = 'if ! false; then # mutation: suppress the real failure-capture scp'
if old not in text:
    raise SystemExit('capture scp mutation target not found')
path.write_text(text.replace(old, new, 1))
PY
if run_contract "$mutated" 0 mutation >"$mutated/mutation-driver.out" 2>&1; then
    fail "negative control stayed green after mutating the real capture behavior"
fi
grep -q 'contract: registered log was not captured byte-identical' "$mutated/mutation-driver.out" || {
    cat "$mutated/mutation-driver.out" >&2
    fail "negative control failed for an unexpected reason"
}

echo "PASS: real _run_long_via_tmux failure diagnostics reached the job log"
echo "PASS: real capture_failure_artifacts ran before the real cleanup_vm reaper"
echo "PASS: real KEEP_VM branch captured evidence without deleting the stub box"
echo "PASS: mutating the fixture copy's real capture behavior turns the contract red"
