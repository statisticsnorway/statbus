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
printf 'nohup sleep 5 > /tmp/detached.log 2>&1 &\n' > "$HARNESS_DIR/scenarios/detached.sh"
check detached-unregistered 1
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
