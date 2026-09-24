#!/bin/bash
# Full shell bootstrap with git/curl fixtures. Go validation is tested in Go.
# These fixtures prove path/flag transport, not installation or schema validity.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-fresh.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
REAL_GIT=$(command -v git)
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
if [ "${EXPECT_STDIN:-}" = pipe ]; then
    [ ! -t 0 ] || { echo 'fixture expected piped stdin' >&2; exit 91; }
    printf '%s\n' "$PIPE_MESSAGE" >&2
    exit 78
fi
if [ "${EXPECT_STDIN:-}" = tty ]; then
    [ -t 0 ] || { echo 'fixture expected terminal stdin' >&2; exit 92; }
    printf 'sb-stdin:tty\n' >> "$TRACE"
fi
[ "${FORCE_TERMINAL:-}" != 1 ] || { mkdir -p tmp; printf 'INVARIANT TEST_GUARD violated: database did not become ready\n' > tmp/install-terminal.txt; }
[ "${FORCE_STEP_FAILURE:-}" != 1 ] || printf '[16/17] Trusted signers      FAILED: release signer approval was declined\n'
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
grep -Fq 'git:clone --depth 1 --no-checkout' "$TRACE"
grep -Fq 'git:-C '"$HOME"'/statbus fetch --depth 1 origin refs/tags/v2026.09.0-rc.02:refs/tags/v2026.09.0-rc.02' "$TRACE"
echo 'PASS: FRESH clone, explicit relative paths and flags forwarded to sb; implicit filenames ignored'
STATBUS_ENV_CONFIG="$EXPECTED_CONFIG" STATBUS_USERS_FILE="$EXPECTED_USERS" \
    bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/output"
echo 'PASS: RESCUE preserves explicit absolute paths without shell-side config imports'
export HOME="$TMP_ROOT/empty-home" EXPECTED_CONFIG='' EXPECTED_USERS=''
mkdir -p "$HOME"
bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/output"
echo 'PASS: absent env vars reach sb, whose fail-fast validation owns the error'
set +e
FORCE_STEP_FAILURE=1 INSTALL_EXIT=47 bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/output" 2>&1
rc=$?
set -e
[ "$rc" = 47 ] || { echo "FAIL: sb failure became $rc"; exit 1; }
grep -Fq 'The installation stopped before it could finish.' "$TMP_ROOT/output"
grep -Fq 'Cause: step 16/17 (Trusted signers) failed: release signer approval was declined' "$TMP_ROOT/output"
grep -Fq 'curl -fsSL https://statbus.org/install.sh | bash' "$TMP_ROOT/output"
! grep -Fq 'SYSTEM UNUSABLE' "$TMP_ROOT/output"
! grep -Fq 'install.sh FAILED at line' "$TMP_ROOT/output"
echo 'PASS: sb validation/installation failure propagates'

set +e
FORCE_TERMINAL=1 INSTALL_EXIT=47 bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/terminal-output" 2>&1
rc=$?
set -e
[ "$rc" = 47 ] || { echo "FAIL: terminal failure became $rc"; exit 1; }
grep -Fq 'Cause: the installation could not finish its final checks' "$TMP_ROOT/terminal-output"
! grep -Fq 'INVARIANT' "$TMP_ROOT/terminal-output"
echo 'PASS: terminal audit detail is translated to plain operator text'

# With no controlling terminal, `echo | install.sh` must preserve piped stdin
# for ./sb, which returns the Go preflight contract. The wrapper propagates the
# precise remedy without a catastrophic banner or support bundle.
export HOME="$TMP_ROOT/pipe-home" EXPECTED_CONFIG='' EXPECTED_USERS=''
mkdir -p "$HOME"
PIPE_MESSAGE='stdin is not a terminal (running under a pipe?). Run interactively with a terminal on stdin, or provide STATBUS_ENV_CONFIG for unattended install.'
set +e
printf '' | EXPECT_STDIN=pipe PIPE_MESSAGE="$PIPE_MESSAGE" python3 -c \
    'import os, sys; os.setsid(); os.execv("/bin/bash", ["bash", sys.argv[1], "--version", "v2026.09.0-rc.02"])' \
    "$ROOT/install.sh" > "$TMP_ROOT/pipe-output" 2>&1
rc=$?
set -e
[ "$rc" = 78 ] || { echo "FAIL: piped preflight became $rc"; cat "$TMP_ROOT/pipe-output"; exit 1; }
grep -Fxq "$PIPE_MESSAGE" "$TMP_ROOT/pipe-output"
if grep -Eq 'SYSTEM UNUSABLE|Contact your administrator|support bundle' "$TMP_ROOT/pipe-output"; then
    echo 'FAIL: preflight refusal printed catastrophic guidance'; cat "$TMP_ROOT/pipe-output"; exit 1
fi
echo 'PASS: no-TTY piped install prints exact remedy without catastrophic banner'

# Reproduce curl|bash under a controlling pseudo-terminal. install.sh itself
# starts with pipe stdin, then must reattach /dev/tty before launching ./sb.
export HOME="$TMP_ROOT/pty-home" INSTALLER_UNDER_TEST="$ROOT/install.sh"
mkdir -p "$HOME"
: > "$TRACE"
EXPECT_STDIN=tty python3 - <<'PY' > "$TMP_ROOT/pty-output" 2>&1
import os
import pty
import sys

pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["bash", "-c", 'cat "$INSTALLER_UNDER_TEST" | bash -s -- --version v2026.09.0-rc.02'])
while True:
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    os.write(1, data)
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
PY
grep -Fxq 'sb-stdin:tty' "$TRACE"
echo 'PASS: curl-pipe install under a PTY reattaches terminal stdin before prompting'
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
    grep -Fq 'git:clone --depth 1 --no-checkout' "$TRACE"
    grep -Fq "fetch --depth 1 origin refs/tags/$expected:refs/tags/$expected" "$TRACE"
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

# The real git sequence used by the fresh path must peel an annotated tag
# without the false "is not a commit" warning, detached-HEAD advice, or a local
# `current` branch. Use an offline file:// origin so this regression is exact
# and deterministic in every local test run.
tag_fixture="$TMP_ROOT/tag-fixture"
mkdir -p "$tag_fixture/source"
"$REAL_GIT" -C "$tag_fixture/source" init -q
"$REAL_GIT" -C "$tag_fixture/source" config user.name fixture
"$REAL_GIT" -C "$tag_fixture/source" config user.email fixture@example.invalid
printf 'fixture\n' > "$tag_fixture/source/file"
"$REAL_GIT" -C "$tag_fixture/source" add file
"$REAL_GIT" -C "$tag_fixture/source" commit -qm fixture
"$REAL_GIT" -C "$tag_fixture/source" tag -a v2026.09.1-rc.18 -m fixture
"$REAL_GIT" init -q --bare "$tag_fixture/origin.git"
"$REAL_GIT" -C "$tag_fixture/source" push -q "$tag_fixture/origin.git" HEAD:master refs/tags/v2026.09.1-rc.18
"$REAL_GIT" -C "$tag_fixture/origin.git" symbolic-ref HEAD refs/heads/master
{
    "$REAL_GIT" clone --depth 1 --no-checkout "file://$tag_fixture/origin.git" "$tag_fixture/install"
    "$REAL_GIT" -C "$tag_fixture/install" fetch --depth 1 origin \
        refs/tags/v2026.09.1-rc.18:refs/tags/v2026.09.1-rc.18
    "$REAL_GIT" -C "$tag_fixture/install" -c advice.detachedHead=false checkout --detach \
        'v2026.09.1-rc.18^{commit}'
} > "$tag_fixture/git-output" 2>&1
[ "$("$REAL_GIT" -C "$tag_fixture/install" describe --exact-match HEAD)" = v2026.09.1-rc.18 ]
[ -z "$("$REAL_GIT" -C "$tag_fixture/install" branch --list current)" ]
if grep -Eqi 'warning:|advice|set up to track|is not a commit|detached HEAD state' "$tag_fixture/git-output"; then
    echo 'FAIL: annotated-tag checkout emitted git warning/advice'; cat "$tag_fixture/git-output"; exit 1
fi
echo 'PASS: annotated tag checks out detached with no current branch or git warnings/advice'
echo 'fresh-installer tests: PASS'
