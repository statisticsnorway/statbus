#!/usr/bin/env bash
# Offline controls for the actual scanner and host/guest collectors.
set -euo pipefail
ROOT=${1:?source root required}
EVIDENCE=${2:?fresh evidence directory required}
ROOT=$(cd "$ROOT" && pwd)
mkdir -p "$EVIDENCE"
EVIDENCE=$(cd "$EVIDENCE" && pwd)
HARNESS_DIR="$EVIDENCE/fixture"
mkdir -p "$HARNESS_DIR"/{lib,scenarios,arcs}
sed -n '/^python3 - /,/^PY$/p' "$ROOT/test/install-recovery/tests/process-log-registration-test.sh" > "$EVIDENCE/scanner.sh"
export HARNESS_DIR
check() {
    local name=$1 expected=$2 status=0
    bash "$EVIDENCE/scanner.sh" > "$EVIDENCE/$name.log" 2>&1 || status=$?
    printf '%s_exit=%s\n' "$name" "$status"
    [[ $status -eq $expected ]]
}
cat > "$HARNESS_DIR/scenarios/control.sh" <<'CASE'
printf '%s\n' local > "$LOCAL_OUTPUT-identity.log"
VM_EXEC cat /home/statbus/guest.log > "$LOCAL_OUTPUT-callback.log"
CASE
check host 0
# The actual C reader is a host subshell, even though arc_to reads a guest.
ARC="$ROOT/test/install-recovery/arcs/c-rollback-resurrection-arc.sh"
sed -n '/^($/,/^C_ARC_PID=\$!$/p' "$ARC" > "$HARNESS_DIR/arcs/host-reader.sh"
check host-background 0
cat >> "$HARNESS_DIR/scenarios/control.sh" <<'CASE'
VM_SCRIPT_INLINE recorder <<'GUEST'
cat > ~/recorder.sh <<'CALLBACK'
printf '%s\n' event >> "$HOME/events.log"
CALLBACK
: > ~/events.log
GUEST
CASE
check guest-unregistered 1
{ printf 'harness_register_log recorder /home/statbus/events.log\n'; cat "$HARNESS_DIR/scenarios/control.sh"; } > "$EVIDENCE/registered.sh"
cp "$EVIDENCE/registered.sh" "$HARNESS_DIR/scenarios/control.sh"
check guest-registered 0
printf 'VM_EXEC bash -c "printf event > /tmp/foreground.log"\n' > "$HARNESS_DIR/scenarios/foreground.sh"
check quoted-guest-unregistered 1
printf 'harness_register_log foreground /tmp/foreground.log\n' > "$HARNESS_DIR/scenarios/foreground.sh"
printf 'VM_EXEC bash -c "printf event > /tmp/foreground.log"\n' >> "$HARNESS_DIR/scenarios/foreground.sh"
check quoted-guest-registered 0
cat > "$HARNESS_DIR/scenarios/background.sh" <<'CASE'
VM_SCRIPT_INLINE reader <<'GUEST'
( printf event ) > /tmp/background.log 2>&1 &
GUEST
CASE
check background-guest-unregistered 1
printf 'harness_register_log reader /tmp/background.log\n' > "$EVIDENCE/background-register.sh"
cat "$HARNESS_DIR/scenarios/background.sh" >> "$EVIDENCE/background-register.sh"
cp "$EVIDENCE/background-register.sh" "$HARNESS_DIR/scenarios/background.sh"
check background-guest-registered 0
cat > "$HARNESS_DIR/scenarios/stdin.sh" <<'CASE'
cat > "$_wedge" <<'WEDGE'
( printf event ) > /tmp/stdin.log 2>&1 &
WEDGE
ssh "${SSH_OPTS[@]}" root@"$VM_IP" "sudo -i -u statbus bash" < "$_wedge"
CASE
check stdin-guest-unregistered 1
printf 'harness_register_log stdin /tmp/stdin.log\n' > "$EVIDENCE/stdin-register.sh"
cat "$HARNESS_DIR/scenarios/stdin.sh" >> "$EVIDENCE/stdin-register.sh"
cp "$EVIDENCE/stdin-register.sh" "$HARNESS_DIR/scenarios/stdin.sh"
check stdin-guest-registered 0
printf 'nohup sleep 5 > /tmp/detached.log 2>&1 &\n' > "$HARNESS_DIR/scenarios/detached.sh"
check detached-unregistered 1
printf 'harness_register_log detached /tmp/detached.log\n' > "$HARNESS_DIR/scenarios/detached.sh"
printf 'nohup sleep 5 > /tmp/detached.log 2>&1 &\n' >> "$HARNESS_DIR/scenarios/detached.sh"
check detached-registered 0
# Execute the actual host reader and EXIT/success output paths under the
# actual LXD stdout collector. Only arc_to and guest cleanup are local doubles.
sed -n '/^_cleanup_crollback_arc() {$/,/^trap _cleanup_crollback_arc EXIT$/p' "$ARC" > "$EVIDENCE/arc-cleanup.sh"
sed -n '/^C_ARC_LOG=$(mktemp)$/,/^C_ARC_PID=\$!$/p' "$ARC" > "$EVIDENCE/arc-reader.sh"
sed -n '/^wait "\$C_ARC_PID"$/,/^C_ARC_LOG=""$/p' "$ARC" > "$EVIDENCE/arc-success.sh"
[[ -s "$EVIDENCE/arc-cleanup.sh" && -s "$EVIDENCE/arc-reader.sh" && -s "$EVIDENCE/arc-success.sh" ]]
cat > "$EVIDENCE/arc-control.sh" <<'CONTROL'
set -euo pipefail
EVIDENCE=$1 mode=$2
export TMPDIR="$EVIDENCE"
C_ARC_PID='' C_ARC_LOG='' C_FULL=fixture C_BRANCH=fixture VM_NAME=fixture
arc_to() {
    printf 'reader-output:%s\n' "$mode"
    if [[ $mode == live ]]; then
        : > "$EVIDENCE/reader-ready"
        while :; do :; done
    fi
    [[ $mode != failed-reader ]] || return 29
}
_dump_crollback_failure_diagnostics() { echo diagnostics; }
cleanup_vm() { printf 'cleanup:%s\n' "$2"; }
source "$EVIDENCE/arc-cleanup.sh"
source "$EVIDENCE/arc-reader.sh"
printf '%s\n' "$C_ARC_PID" > "$EVIDENCE/reader.pid"
if [[ $mode == live ]]; then
    while [[ ! -f "$EVIDENCE/reader-ready" ]]; do sleep 0.01; done
    exit 47
fi
source "$EVIDENCE/arc-success.sh"
CONTROL
# shellcheck disable=SC1091 # pure local process-group helpers, no bootstrap
source "$ROOT/test/install-recovery/lxd/proc-tree.sh"
for mode in success failed-reader live; do
    expected=0
    [[ $mode != failed-reader ]] || expected=29
    [[ $mode != live ]] || expected=47
    status=0
    run_bounded 10 1 "$EVIDENCE/arc-$mode.log" bash "$EVIDENCE/arc-control.sh" "$EVIDENCE" "$mode" || status=$?
    printf 'host_arc_%s_exit=%s\n' "$mode" "$status"
    [[ $status -eq $expected ]]
    grep -Fxq "reader-output:$mode" "$EVIDENCE/arc-$mode.log"
    [[ $(grep -c '^cleanup:' "$EVIDENCE/arc-$mode.log") -eq 1 ]]
    grep -Fxq "cleanup:$expected" "$EVIDENCE/arc-$mode.log"
    if [[ $expected -eq 0 ]]; then
        ! grep -q '^diagnostics$' "$EVIDENCE/arc-$mode.log"
    else
        grep -Fxq diagnostics "$EVIDENCE/arc-$mode.log"
    fi
    ! kill -0 "$(cat "$EVIDENCE/reader.pid")" 2>/dev/null
done
# Actual host writes and RUN_DIR artifact copy, without guest registration.
SCENARIO="$ROOT/test/install-recovery/scenarios/5-install-source-image-identity-proof.sh"
RUN_DIR="$EVIDENCE/host"
LXD_FLEET_ARTIFACT_DIR="$EVIDENCE/artifacts"
mkdir -p "$RUN_DIR" "$LXD_FLEET_ARTIFACT_DIR"
export PROOF_LOG_PREFIX="$RUN_DIR/control"
export CANDIDATE_PATH=scheduled INSTALL_TARGET_TAG=fixture TARGET_SHA=fixture CALLBACK_EVENTS=guest-event
VM_EXEC() { [[ "$*" == 'cat /home/statbus/statbus-proof-callback.log' ]] || return 97; printf '%s\n' guest-event; }
# shellcheck disable=SC2016 # literal source tokens
sed -n '/^printf .* > "\$PROOF_LOG_PREFIX-identity.log"$/p; /VM_EXEC cat .* > "\$PROOF_LOG_PREFIX-callback.log"/p; /printf .* > "\$PROOF_LOG_PREFIX-callback.log"$/p' "$SCENARIO" > "$EVIDENCE/host-writes.sh"
# shellcheck disable=SC1090,SC1091 # extracted actual host statements
source "$EVIDENCE/host-writes.sh"
# shellcheck disable=SC2016 # literal source tokens
sed -n '/find "\$RUN_DIR" -maxdepth 1 -name .*\.log.*-exec cp/p' "$ROOT/test/install-recovery/lxd/run-forks.sh" > "$EVIDENCE/host-collect.sh"
# shellcheck disable=SC1090,SC1091 # extracted actual collection command
source "$EVIDENCE/host-collect.sh"
cmp "$RUN_DIR/control-identity.log" "$LXD_FLEET_ARTIFACT_DIR/control-identity.log"
cmp "$RUN_DIR/control-callback.log" "$LXD_FLEET_ARTIFACT_DIR/control-callback.log"
echo 'host_actual_retention_exit=0'
# Native registration, with refusing SSH/timeout doubles. No bootstrap source.
sed -n '/^harness_register_log() {$/,/^}$/p' "$ROOT/test/install-recovery/lib/vm-bootstrap.sh" > "$EVIDENCE/register.sh"
# shellcheck disable=SC1090,SC1091
source "$EVIDENCE/register.sh"
# shellcheck disable=SC2034 # consumed by extracted helper
SSH_OPTS=(fixture-option) VM_IP=fixture-guest
ssh() {
    [[ "$1" == fixture-option && "$2" == root@fixture-guest && "$3" == 'install -d -m 0755 /var/tmp/statbus-harness && cat >> /var/tmp/statbus-harness/logs.manifest' ]] || return 98
    cat >> "$EVIDENCE/guest.manifest"
    printf 'register\n' >> "$EVIDENCE/order"
}
timeout() { [[ "$1" == 30 && "$2" == ssh ]] || return 99; shift; "$@"; }
sed -n '/^harness_register_log source-proof-callback /p' "$SCENARIO" > "$EVIDENCE/scenario-register.sh"
[[ -s "$EVIDENCE/scenario-register.sh" ]]
# shellcheck disable=SC1090,SC1091
source "$EVIDENCE/scenario-register.sh"
printf 'source-proof-callback\t/home/statbus/statbus-proof-callback.log\n' | cmp - "$EVIDENCE/guest.manifest"
awk '/^harness_register_log source-proof-callback / {registered=1} /^VM_SCRIPT_INLINE arm-local-callback / {exit !registered}' "$SCENARIO"
# Actual callback write body, stopping before config operations.
sed -n "/^VM_SCRIPT_INLINE arm-local-callback <<'REMOTE'$/,/^cd ~\/statbus$/p" "$SCENARIO" | sed '1d;$d' > "$EVIDENCE/arm.sh"
HOME="$EVIDENCE/guest-home"
mkdir -p "$HOME"
bash -euo pipefail "$EVIDENCE/arm.sh"
STATBUS_EVENT=event STATBUS_VERSION=fixture bash "$HOME/statbus-proof-callback.sh"
printf 'guest-write\n' >> "$EVIDENCE/order"
printf 'register\nguest-write\n' | cmp - "$EVIDENCE/order"
printf 'event|fixture\n' | cmp - "$HOME/statbus-proof-callback.log"
echo 'guest_real_registration_before_write_exit=0'
