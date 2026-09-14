#!/bin/bash
# Execute the real helper's generated wrapper with a fake remote filesystem and
# candidate installer. Tests dispatch/exit propagation, NOT a real installation.
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-369-sha.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/home" "$TMP_ROOT/bin" "$TMP_ROOT/tmp"
export TRACE="$TMP_ROOT/trace" HOME="$TMP_ROOT/home"
# Used by the sourced production function below.
# shellcheck disable=SC2034
HARNESS_ROOT="$TMP_ROOT"
# shellcheck disable=SC2034 # consumed by extracted production helper
HARNESS_DEPLOYMENT_MODE=private
SHA=0123456789abcdef0123456789abcdef01234567
TAG=v2026.09.0-rc.02
# shellcheck disable=SC2034
SSH_OPTS=(-o BatchMode=yes)
# Source ONLY the production helper, not the credential/bootstrap entrypoints.
sed -n '/^install_statbus_at_sha() {$/,/^}$/p' "$TEST_DIR/../lib/vm-bootstrap.sh" > "$TMP_ROOT/helper.sh"
# shellcheck disable=SC1090,SC1091 # generated production helper
source "$TMP_ROOT/helper.sh"
_check_name_safety() { :; }
_hcloud_server_ip() { echo lookup >> "$TRACE"; echo 192.0.2.1; }
_wait_for_ssh() { :; }
ssh() { :; }
scp() {
    case "$5" in
        *:/tmp/statbus-install.sh) cp "$4" "$TMP_ROOT/candidate-install.sh" ;;
        *:/tmp/install.sh) cp "$4" "$TMP_ROOT/generated.sh" ;;
        *) echo "unexpected scp: $*" >&2; return 99 ;;
    esac
}
_run_long_via_tmux() {
    # The wrapper must not clone, procure a binary or call sb itself.
    if grep -Eq 'git clone|docker |curl |\./sb install' "$TMP_ROOT/generated.sh"; then
        echo 'FAIL: wrapper bypasses product fresh installer'; return 99
    fi
    sed "s|/tmp/env-config|$TMP_ROOT/env-config|g; s|/tmp/users.yml|$TMP_ROOT/users.yml|g; s|/tmp/statbus-install.sh|$TMP_ROOT/candidate-install.sh|g" \
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
cat > "$HARNESS_ROOT/install.sh" <<'MOCK'
#!/bin/bash
set -euo pipefail
[ ! -e "$HOME/statbus" ]
[ "$STATBUS_ENV_CONFIG" = "$HOME/install-input.env" ]
grep -Fxq 'CADDY_DEPLOYMENT_MODE=private' "$STATBUS_ENV_CONFIG"
[ "$(wc -l < "$STATBUS_ENV_CONFIG" | tr -d ' ')" = 5 ]
[ "$(cat "$STATBUS_USERS_FILE")" = users-fixture ]
grep -Fxq 'TRUST_GITHUB_USER=jhf' "$STATBUS_ENV_CONFIG"
[ "$STATBUS_INSTALL_VERSION" = v2026.09.0-rc.02 ]
echo "candidate-install.sh:$*" >> "$TRACE"
exit "${INSTALL_EXIT:-0}"
MOCK
install_statbus_at_sha statbus-recovery-fixture "$SHA" "$TAG"
if grep -Eq "git:(clone|checkout|fetch)" "$TRACE"; then echo "FAIL: pre-clone"; exit 1; fi
grep -Fxq "candidate-install.sh:--non-interactive" "$TRACE"
if grep -q FORBIDDEN "$TRACE"; then echo "FAIL: unexpected procurement"; exit 1; fi
echo 'PASS: shipped candidate installer invoked with tag and explicit input paths while repo absent'
# Run outside an if-condition so Bash errexit semantics match the real caller.
set +e
(export INSTALL_EXIT=47; set -e; install_statbus_at_sha statbus-recovery-fixture "$SHA" "$TAG")
rc=$?
set -e
[ "$rc" = 47 ] || { echo "FAIL: installer failure became rc=$rc"; exit 1; }
if grep -q FORBIDDEN "$TRACE"; then echo "FAIL: unexpected procurement"; exit 1; fi
echo 'PASS: candidate installer failure propagated without build/image fallback'
mkdir -p "$HOME/statbus/.git"
set +e
(set -e; install_statbus_at_sha statbus-recovery-fixture "$SHA" "$TAG")
rc=$?
set -e
[ "$rc" = 70 ] || { echo 'FAIL: accepted existing repo'; exit 1; }
rmdir "$HOME/statbus/.git" "$HOME/statbus"
mv "$TMP_ROOT/users.yml" "$TMP_ROOT/saved-users"
set +e
(set -e; install_statbus_at_sha statbus-recovery-fixture "$SHA" "$TAG")
rc=$?
set -e
[ "$rc" != 0 ] || { echo 'FAIL: accepted missing input'; exit 1; }
mv "$TMP_ROOT/saved-users" "$TMP_ROOT/users.yml"
echo 'PASS: existing repository and missing users input refused'
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
