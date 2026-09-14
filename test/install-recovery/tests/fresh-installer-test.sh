#!/bin/bash
# Full shell bootstrap with git/curl fixtures. Go validation is tested in Go.
# These fixtures prove path/flag transport, not installation or schema validity.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-fresh.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/home" "$TMP_ROOT/inputs with spaces"
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
echo 'fresh-installer tests: PASS'
