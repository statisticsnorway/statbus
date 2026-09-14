#!/bin/bash
# Full shell bootstrap with git/curl fixtures. Go validation is tested in Go.
# These fixtures prove path/flag transport, not installation or schema validity.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-fresh.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/home" "$TMP_ROOT/inputs with spaces"
unset STATBUS_INSTALL_VERSION
export HOME="$TMP_ROOT/home" TRACE="$TMP_ROOT/trace"
cat > "$TMP_ROOT/bin/git" <<'MOCK'
#!/bin/bash
set -eu
printf 'git:%s\n' "$*" >> "$TRACE"
if [ "$1" = clone ]; then
    for destination in "$@"; do :; done
    [ ! -e "$destination" ]
    mkdir -p "$destination/.git"
fi
MOCK
cat > "$TMP_ROOT/bin/curl" <<'MOCK'
#!/bin/bash
set -eu
printf 'curl:%s\n' "$*" >> "$TRACE"
case "$*" in
    *'/releases/latest'*) printf '{"tag_name": "v2026.09.0"}\n'; exit 0 ;;
esac
while [ "$1" != -o ]; do shift; done
cat > "$2" <<'SB'
#!/bin/bash
set -eu
if [ "$1" = --version ]; then echo 'fixture version'; exit 0; fi
if [ "$1" != install ]; then exit 0; fi
printf 'sb:%s\n' "$*" >> "$TRACE"
[ "${STATBUS_ENV_CONFIG:-}" = "$EXPECTED_CONFIG" ]
[ "${STATBUS_USERS_FILE:-}" = "$EXPECTED_USERS" ]
# Shell bootstrap must leave input validation and importing to the product.
[ ! -e .env.config ] && [ ! -e .users.yml ]
exit "${INSTALL_EXIT:-0}"
SB
MOCK
cat > "$TMP_ROOT/bin/docker" <<'MOCK'
#!/bin/bash
exit 99
MOCK
chmod +x "$TMP_ROOT/bin/"*
export PATH="$TMP_ROOT/bin:$PATH"
echo configuration > "$TMP_ROOT/inputs with spaces/config.env"
echo users > "$TMP_ROOT/inputs with spaces/users.yml"
# Old implicit inputs must be ignored, never discovered or copied.
echo stale > "$HOME/.statbus.env.config"
echo stale > "$HOME/.statbus.users.yml"
export EXPECTED_CONFIG="$TMP_ROOT/inputs with spaces/config.env"
export EXPECTED_USERS="$TMP_ROOT/inputs with spaces/users.yml"
(cd "$TMP_ROOT" && STATBUS_ENV_CONFIG='inputs with spaces/config.env' STATBUS_USERS_FILE='inputs with spaces/users.yml' \
    bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive --trust-github-user jhf) > "$TMP_ROOT/output"
grep -Fxq 'sb:install --non-interactive --trust-github-user jhf' "$TRACE"
grep -Fq 'git:clone --depth 1 --branch v2026.09.0-rc.02' "$TRACE"
echo 'PASS: FRESH clone, explicit relative paths and flags forwarded to sb; implicit filenames ignored'
STATBUS_ENV_CONFIG="$EXPECTED_CONFIG" STATBUS_USERS_FILE="$EXPECTED_USERS" \
    bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/output"
echo 'PASS: RESCUE preserves explicit absolute paths without shell-side config imports'
export HOME="$TMP_ROOT/empty-home" EXPECTED_CONFIG='' EXPECTED_USERS=''
mkdir -p "$HOME"
bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/output"
echo 'PASS: absent env vars reach sb, whose fail-fast validation owns the error'
set +e
INSTALL_EXIT=47 bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/output" 2>&1
rc=$?
set -e
[ "$rc" = 47 ] || { echo "FAIL: sb failure became $rc"; exit 1; }
echo 'PASS: sb validation/installation failure propagates'
# Exercise real parser/resolver, with fixture transports only. Nothing reaches
# GitHub, Docker or a database. Each successful case starts from an empty home.
for shape in env matching default; do
    export HOME="$TMP_ROOT/version-$shape"
    mkdir -p "$HOME"
    : > "$TRACE"
    args=(--non-interactive)
    case "$shape" in
        env) export STATBUS_INSTALL_VERSION=v2026.09.0-rc.02 ;;
        matching) export STATBUS_INSTALL_VERSION=v2026.09.0-rc.02; args+=(--version "$STATBUS_INSTALL_VERSION") ;;
        default) unset STATBUS_INSTALL_VERSION ;;
    esac
    bash "$ROOT/install.sh" "${args[@]}" > "$TMP_ROOT/output"
    expected=${STATBUS_INSTALL_VERSION:-v2026.09.0}
    grep -Fq "git:clone --depth 1 --branch $expected" "$TRACE"
    if [ "$shape" = default ]; then grep -Fq '/releases/latest' "$TRACE"; fi
    echo "PASS: version $shape resolves $expected"
done
export STATBUS_INSTALL_VERSION=v2026.09.0-rc.02
for shape in version channel commit; do
    : > "$TRACE"
    case "$shape" in
        version) args=(--version v2026.09.0) ;;
        channel) args=(--channel stable) ;;
        commit) args=(--commit 1111111111111111111111111111111111111111) ;;
    esac
    if bash "$ROOT/install.sh" "${args[@]}" > "$TMP_ROOT/output" 2>&1; then
        echo "FAIL: version env conflict with $shape accepted"; exit 1
    fi
    grep -Eq 'conflicts|mutually exclusive' "$TMP_ROOT/output"
    [ ! -s "$TRACE" ] || { echo 'FAIL: conflict reached network/clone'; exit 1; }
    echo "PASS: version environment conflict with $shape refuses before side effects"
done
unset STATBUS_INSTALL_VERSION
echo 'fresh-installer tests: PASS'
