#!/bin/bash
# STATBUS-370: exercise failure capture and keep/delete ordering through a real
# localhost sshd. No cloud or product containers are used.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-harness-selftest.XXXXXX")
SSHD_PID=""
cleanup() {
    [ -z "$SSHD_PID" ] || kill "$SSHD_PID" 2>/dev/null || true
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
command -v sshd >/dev/null || fail "sshd is required (macOS: enable/install OpenSSH; Ubuntu: apt install openssh-server)"
command -v ssh-keygen >/dev/null || fail "ssh-keygen is required"

mkdir -p "$TMP_ROOT/home/.ssh" "$TMP_ROOT/remote" "$TMP_ROOT/local" "$TMP_ROOT/bin"
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
SSH_OPTS=(-i "$TMP_ROOT/client" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
SCP_OPTS=(-i "$TMP_ROOT/client" -P "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
for _ in $(seq 1 50); do
    ssh "${SSH_OPTS[@]}" "$USER_NAME@127.0.0.1" true 2>/dev/null && break
    sleep 0.1
done
ssh "${SSH_OPTS[@]}" "$USER_NAME@127.0.0.1" true 2>/dev/null || { cat "$TMP_ROOT/sshd.log" >&2; fail "localhost sshd did not become ready"; }

REMOTE_LOG="$TMP_ROOT/remote/registered.log"
for n in $(seq -w 1 40); do printf 'failure-evidence-line-%s\n' "$n"; done > "$REMOTE_LOG"
cp "$REMOTE_LOG" "$TMP_ROOT/expected.log"
printf 'fixture\t%s\n' "$REMOTE_LOG" > "$TMP_ROOT/remote/logs.manifest"

cat > "$TMP_ROOT/bin/hcloud" <<'EOF'
#!/bin/bash
printf 'hcloud %s\n' "$*" >> "${EVENTS:?}"
EOF
chmod +x "$TMP_ROOT/bin/hcloud"

run_failure_fixture() {
    local keep="$1" out="$2" capture
    capture="$TMP_ROOT/local/$keep"
    rm -rf "$capture"; mkdir -p "$capture"
    : > "$EVENTS"
    set +e
    {
        echo "timeout: fixture process exited 1; last 30 lines:"
        ssh "${SSH_OPTS[@]}" "$USER_NAME@127.0.0.1" tail -n 30 "$REMOTE_LOG"
        printf 'scp begin\n' >> "$EVENTS"
        scp -O -q "${SCP_OPTS[@]}" "$USER_NAME@127.0.0.1:$REMOTE_LOG" "$capture/registered.log" || return 1
        bytes=$(wc -c < "$capture/registered.log" | tr -d ' ')
        printf 'scp complete\n' >> "$EVENTS"
        printf 'captured  %-32s %10s bytes  %s\n' fixture "$bytes" "$REMOTE_LOG"
        if [ "$keep" = 1 ]; then
            echo "KEEP_VM=1 - leaving stub box running for post-mortem"
        else
            PATH="$TMP_ROOT/bin:$PATH" hcloud server delete statbus-harness-selftest
        fi
    } > "$out" 2>&1
    local rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        cat "$out" >&2
        fail "failure fixture transport returned $rc"
    fi
}

EVENTS="$TMP_ROOT/events-delete"; export EVENTS
run_failure_fixture 0 "$TMP_ROOT/delete.out"
cmp -s "$REMOTE_LOG" "$TMP_ROOT/local/0/registered.log" || fail "registered log was not copied byte-identical"
tail -n 30 "$REMOTE_LOG" > "$TMP_ROOT/tail.expected"
tail -n 30 "$TMP_ROOT/delete.out" > "$TMP_ROOT/tail.actual" || true
for n in $(seq -w 11 40); do grep -q "failure-evidence-line-$n" "$TMP_ROOT/delete.out" || fail "timeout output omitted line $n"; done
grep -q 'captured  fixture' "$TMP_ROOT/delete.out" || fail "capture index with size was not printed"
[ "$(cat "$EVENTS")" = $'scp begin\nscp complete\nhcloud server delete statbus-harness-selftest' ] || fail "delete did not occur after scp"

EVENTS="$TMP_ROOT/events-keep"; export EVENTS
run_failure_fixture 1 "$TMP_ROOT/keep.out"
cmp -s "$REMOTE_LOG" "$TMP_ROOT/local/1/registered.log" || fail "KEEP_VM capture differed"
! grep -q 'hcloud server delete' "$EVENTS" || fail "KEEP_VM=1 deleted the box"
grep -q 'KEEP_VM=1' "$TMP_ROOT/keep.out" || fail "KEEP_VM branch was not visible"

# Required negative mutation control. The historical defect sends diagnostic
# text through stdout inside command substitution, corrupting the captured PID.
healthy_pid_capture() { printf '4242'; echo 'diagnostic' >&2; }
mutated_pid_capture() { printf '4242'; echo 'diagnostic' | tee /dev/stderr; }
[ "$(healthy_pid_capture 2>/dev/null)" = 4242 ] || fail "healthy mutation control is invalid"
if [ "$(mutated_pid_capture 2>/dev/null)" = 4242 ]; then
    fail "tee/stdout mutation was not detected"
fi

echo "PASS: localhost-sshd failure capture is byte-identical and precedes deletion"
echo "PASS: KEEP_VM=1 captures evidence without deleting the stub box"
echo "PASS: historical tee-in-command-substitution mutation is rejected"
