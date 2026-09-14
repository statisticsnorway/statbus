#!/bin/bash
# Complete product bootstrap with local git/curl fixtures. No network or Docker.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-fresh.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/home"
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
printf 'sb:%s\n' "$*" >> "$TRACE"
if [ "${EXPECT_CONFIG:-yes}" = yes ]; then
    [ "$(cat .env.config)" = configuration ]
    [ "$(cat .users.yml)" = users ]
else
    [ ! -e .env.config ] && [ ! -e .users.yml ]
fi
exit "${INSTALL_EXIT:-0}"
SB
MOCK
cat > "$TMP_ROOT/bin/docker" <<'MOCK'
#!/bin/bash
exit 99
MOCK
chmod +x "$TMP_ROOT/bin/"*
export PATH="$TMP_ROOT/bin:$PATH"
echo configuration > "$HOME/.statbus.env.config"
echo users > "$HOME/.statbus.users.yml"
bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive --trust-github-user jhf > "$TMP_ROOT/output"
grep -Fxq 'sb:install --non-interactive --trust-github-user jhf' "$TRACE"
grep -Fq 'git:clone --depth 1 --branch v2026.09.0-rc.02' "$TRACE"
[ -f "$HOME/.statbus.env.config" ] && [ -f "$HOME/.statbus.users.yml" ]
for config in "$HOME/statbus/.env.config" "$HOME/statbus/.users.yml"; do
    [ "$(ls -l "$config" | cut -c1-10)" = '-rw-------' ]
done
echo 'PASS: full fresh installer clones, imports home config, forwards supported flags'
# Rescue must not overwrite the configuration with stale unattended inputs.
echo stale > "$HOME/.statbus.env.config"
echo stale > "$HOME/.statbus.users.yml"
bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/output"
echo 'PASS: rescue preserves installed configuration'
# Another empty home with absent optional inputs reaches sb without inventing files.
export HOME="$TMP_ROOT/empty-home" EXPECT_CONFIG=no
mkdir -p "$HOME"
bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/output"
echo 'PASS: absent inputs are optional'
export HOME="$TMP_ROOT/bad-home" EXPECT_CONFIG=yes
mkdir -p "$HOME/.statbus.env.config"
echo users > "$HOME/.statbus.users.yml"
: > "$TRACE"
if bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/output" 2>&1; then
    echo 'FAIL: invalid config input accepted'; exit 1
fi
if grep -q '^sb:install' "$TRACE"; then echo 'FAIL: sb ran after copy failure'; exit 1; fi
echo 'PASS: config copy failure stops before sb install'
echo 'fresh-installer tests: PASS'
