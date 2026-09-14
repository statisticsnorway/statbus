#!/bin/bash
# Execute the real helper's generated wrapper with a fake remote filesystem and
# candidate installer. Tests dispatch/exit propagation, NOT a real installation.
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-369-sha.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/home/statbus/.git" "$TMP_ROOT/bin" "$TMP_ROOT/tmp"
export TRACE="$TMP_ROOT/trace" HOME="$TMP_ROOT/home"
# Used by the sourced production function below.
# shellcheck disable=SC2034
HARNESS_ROOT="$TMP_ROOT"
SHA=0123456789abcdef0123456789abcdef01234567
TAG=v2026.09.0-rc.02
# shellcheck disable=SC2034
SSH_OPTS=(-o BatchMode=yes)
# Source ONLY the production helper, not the credential/bootstrap entrypoints.
sed -n '/^install_statbus_at_sha() {$/,/^}$/p' "$TEST_DIR/../lib/vm-bootstrap.sh" > "$TMP_ROOT/helper.sh"
# shellcheck disable=SC1090
source "$TMP_ROOT/helper.sh"
_check_name_safety() { :; }
_hcloud_server_ip() { echo lookup >> "$TRACE"; echo 192.0.2.1; }
_wait_for_ssh() { :; }
ssh() { :; }
scp() { cp "$4" "$TMP_ROOT/generated.sh"; }
_run_long_via_tmux() {
    # The wrapper must retain the established on-box config/users placement.
    grep -Fxq 'cp /tmp/env-config .env.config' "$TMP_ROOT/generated.sh"
    grep -Fxq 'cp /tmp/users.yml .users.yml' "$TMP_ROOT/generated.sh"
    # Redirect only those absolute fixture inputs for this offline execution.
    sed "s|/tmp/env-config|$TMP_ROOT/env-config|g; s|/tmp/users.yml|$TMP_ROOT/users.yml|g" \
        "$TMP_ROOT/generated.sh" > "$TMP_ROOT/execute.sh"
    bash -n "$TMP_ROOT/generated.sh"
    bash "$TMP_ROOT/execute.sh"
}
cat > "$TMP_ROOT/bin/git" <<'MOCK'
#!/bin/bash
printf 'git:%s\n' "$*" >> "$TRACE"
case "$*" in
    *rev-parse*) echo "${RESOLVED_SHA:-0123456789abcdef0123456789abcdef01234567}" ;;
esac
MOCK
# Executing any procurement outside the candidate installer is forbidden here.
for command in docker go curl; do
    cat > "$TMP_ROOT/bin/$command" <<'MOCK'
#!/bin/bash
echo "FORBIDDEN:$0 $*" >> "$TRACE"
exit 99
MOCK
done
chmod +x "$TMP_ROOT/bin/"*
export PATH="$TMP_ROOT/bin:$PATH"
echo config-fixture > "$TMP_ROOT/env-config"
echo users-fixture > "$TMP_ROOT/users.yml"
cat > "$HOME/statbus/install.sh" <<'MOCK'
#!/bin/bash
set -euo pipefail
[ "$(cat .env.config)" = config-fixture ]
[ "$(cat .users.yml)" = users-fixture ]
echo "candidate-install.sh:$*" >> "$TRACE"
exit "${INSTALL_EXIT:-0}"
MOCK
install_statbus_at_sha statbus-recovery-fixture "$SHA" "$TAG"
grep -Fxq "git:checkout -q $SHA" "$TRACE"
grep -Fxq "candidate-install.sh:--version $TAG --trust-github-user jhf" "$TRACE"
if grep -q FORBIDDEN "$TRACE"; then echo "FAIL: unexpected procurement"; exit 1; fi
echo 'PASS: candidate tree installer invoked with tag after unchanged config/users placement'
# Run outside an if-condition so Bash errexit semantics match the real caller.
set +e
(export INSTALL_EXIT=47; set -e; install_statbus_at_sha statbus-recovery-fixture "$SHA" "$TAG")
rc=$?
set -e
[ "$rc" = 47 ] || { echo "FAIL: installer failure became rc=$rc"; exit 1; }
if grep -q FORBIDDEN "$TRACE"; then echo "FAIL: unexpected procurement"; exit 1; fi
echo 'PASS: candidate installer failure propagated without build/image fallback'
: > "$TRACE"
if RESOLVED_SHA=deadbeef install_statbus_at_sha statbus-recovery-fixture "$SHA" "$TAG"; then
    echo 'FAIL: mismatched tag accepted'; exit 1
fi
if grep -q lookup "$TRACE"; then echo "FAIL: VM accessed"; exit 1; fi
if install_statbus_at_sha statbus-recovery-fixture "$SHA" 'not-a-tag'; then
    echo 'FAIL: invalid tag accepted'; exit 1
fi
if grep -q lookup "$TRACE"; then echo "FAIL: VM accessed"; exit 1; fi
echo 'PASS: invalid/mismatched tag refused before VM access'
echo 'install-at-sha tests: PASS'
