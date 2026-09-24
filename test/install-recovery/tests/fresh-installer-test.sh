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
export HOME="$TMP_ROOT/home" TRACE="$TMP_ROOT/trace" FILTER_SOURCE="$ROOT/ops/install-terminal-output.awk"
cat > "$TMP_ROOT/bin/git" <<'MOCK'
#!/bin/bash
set -eu
printf 'git:%s\n' "$*" >> "$TRACE"
if [ "$1" = clone ]; then
    for destination in "$@"; do :; done
    [ ! -e "$destination" ]
    mkdir -p "$destination/.git" "$destination/ops"
    cp "$FILTER_SOURCE" "$destination/ops/install-terminal-output.awk"
fi
MOCK
cat > "$TMP_ROOT/bin/curl" <<'MOCK'
#!/bin/bash
set -eu
printf 'curl:%s\n' "$*" >> "$TRACE"
case "$*" in
    *'/releases/latest'*) printf '{"tag_name": "v2026.09.0"}\n'; exit 0 ;;
    *'/releases?per_page=50'*) printf '[{"tag_name": "v2026.09.0-rc.02"}]\n'; exit 0 ;;
esac
while [ "$1" != -o ]; do shift; done
cat > "$2" <<'SB'
#!/bin/bash
set -eu
if [ "$1" = --version ]; then echo 'fixture version'; exit 0; fi
if [ "$1" != install ]; then exit 0; fi
printf 'sb:%s\n' "$*" >> "$TRACE"
if [ "${EMIT_DNS_ADVICE:-}" = 1 ]; then
    printf '  candidate.example is not confirmed in public DNS, so an automatic public certificate cannot be promised, and local development is recommended for testing until the name is published and inbound port 80 is allowed.\n'
fi
if [ "${EMIT_RERUN:-}" = 1 ]; then
    printf 'port 80 is in use by another program. Your answers are saved. Then run the same install command again: %s\n' "$STATBUS_INSTALL_RERUN_COMMAND"
    exit 78
fi
if [ "${EXPECT_RESTART_MARKER:-}" = 1 ]; then
    grep -Fq '"trigger":"restart"' tmp/upgrade-in-progress.json || exit 93
    if [ "${FAIL_RESTART_RESTORE:-}" = 1 ]; then
        printf 'a restart is still running, or its services could not be restored. Wait for it to finish, then run the same install command again: %s\n' "$STATBUS_INSTALL_RERUN_COMMAND"
        exit 78
    fi
    printf 'The previous restart finished. Continuing installation.\n'
    rm tmp/upgrade-in-progress.json
fi
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
[ "${EMIT_ROLLBACK:-}" != 1 ] || { printf 'UPGRADE_FAILED_ROLLED_BACK\n'; exit 75; }
[ "${EMIT_CLASSIFIED:-}" != 1 ] || { printf '[8/17] Services             FAILED: This part of installation could not finish.\nINSTALL_CAUSE: The database rejected its password.\nINSTALL_FIX: Check the saved database credentials and synchronize them with the running database, then retry.\n'; exit 47; }
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
EMIT_DNS_ADVICE=1 STATBUS_ENV_CONFIG="$EXPECTED_CONFIG" STATBUS_USERS_FILE="$EXPECTED_USERS" \
    bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/dns-output"
grep -Fq 'candidate.example is not confirmed in public DNS' "$TMP_ROOT/dns-output"
echo 'PASS: answers-file install surfaces public DNS recommendation'
set +e
(cd "$TMP_ROOT" && EMIT_RERUN=1 STATBUS_ENV_CONFIG='inputs with spaces/config.env' STATBUS_USERS_FILE='inputs with spaces/users.yml' \
    bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive) > "$TMP_ROOT/rerun-output" 2>&1
rc=$?
set -e
[ "$rc" = 78 ]
grep -Fq 'STATBUS_ENV_CONFIG=' "$TMP_ROOT/rerun-output"
grep -Fq 'STATBUS_USERS_FILE=' "$TMP_ROOT/rerun-output"
grep -Fq 'bash -s -- --version v2026.09.0-rc.02 --non-interactive' "$TMP_ROOT/rerun-output"
grep -Fq "${TMP_ROOT}/inputs\\ with\\ spaces/config.env" "$TMP_ROOT/rerun-output"
echo 'PASS: rerun retains version, flags and absolute quoted answer paths'
# A clean rollback is an exit-75 outcome, but its printed retry must preserve
# the exact release selection and answer files too.
for selection in version channel; do
    if [ "$selection" = version ]; then args=(--version v2026.09.0-rc.02); else args=(--channel prerelease); fi
    (cd "$TMP_ROOT" && EMIT_ROLLBACK=1 STATBUS_ENV_CONFIG='inputs with spaces/config.env' STATBUS_USERS_FILE='inputs with spaces/users.yml' \
        bash "$ROOT/install.sh" "${args[@]}" --non-interactive) > "$TMP_ROOT/rollback-$selection-output" 2>&1
    grep -Fq 'UPGRADE FAILED' "$TMP_ROOT/rollback-$selection-output"
    grep -Fq "bash -s -- ${args[*]} --non-interactive" "$TMP_ROOT/rollback-$selection-output"
    grep -Fq "${TMP_ROOT}/inputs\\ with\\ spaces/config.env" "$TMP_ROOT/rollback-$selection-output"
    grep -Fq 'STATBUS_USERS_FILE=' "$TMP_ROOT/rollback-$selection-output"
done
echo 'PASS: clean rollback retains selected version/channel and both answer files'
set +e
EMIT_CLASSIFIED=1 STATBUS_ENV_CONFIG="$EXPECTED_CONFIG" STATBUS_USERS_FILE="$EXPECTED_USERS" \
    bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/classified-output" 2>&1
rc=$?
set -e
[ "$rc" = 47 ]
grep -Fq 'Cause: The database rejected its password.' "$TMP_ROOT/classified-output"
grep -Fq 'Outside fix: Check the saved database credentials and synchronize them with the running database, then retry.' "$TMP_ROOT/classified-output"
echo 'PASS: classified step cause and outside fix reach wrapper without raw errors'
# The real wrapper must leave a freed restart record for Go to inspect.
mkdir -p "$HOME/statbus/tmp"
printf '{"trigger":"restart","restart":{"profile":"all"}}\n' > "$HOME/statbus/tmp/upgrade-in-progress.json"
EXPECT_RESTART_MARKER=1 STATBUS_ENV_CONFIG="$EXPECTED_CONFIG" STATBUS_USERS_FILE="$EXPECTED_USERS" \
    bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/stale-restart-output"
[ ! -e "$HOME/statbus/tmp/upgrade-in-progress.json" ]
echo 'PASS: stale restart record reaches Go installer intact'
# Go's failed-restoration refusal must survive the real shell wrapper with all
# selected release and answer files intact, not collapse to a bare curl.
printf '{"trigger":"restart","restart":{"profile":"all"}}\n' > "$HOME/statbus/tmp/upgrade-in-progress.json"
set +e
(cd "$TMP_ROOT" && EXPECT_RESTART_MARKER=1 FAIL_RESTART_RESTORE=1 STATBUS_ENV_CONFIG='inputs with spaces/config.env' STATBUS_USERS_FILE='inputs with spaces/users.yml' \
    bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive) > "$TMP_ROOT/stale-restart-failed-output" 2>&1
rc=$?
set -e
[ "$rc" = 78 ] || { cat "$TMP_ROOT/stale-restart-failed-output" >&2; exit 1; }
grep -Fq 'a restart is still running, or its services could not be restored' "$TMP_ROOT/stale-restart-failed-output"
grep -Fq 'bash -s -- --version v2026.09.0-rc.02 --non-interactive' "$TMP_ROOT/stale-restart-failed-output"
grep -Fq "${TMP_ROOT}/inputs\\ with\\ spaces/config.env" "$TMP_ROOT/stale-restart-failed-output"
grep -Fq 'STATBUS_USERS_FILE=' "$TMP_ROOT/stale-restart-failed-output"
set +e
EXPECT_RESTART_MARKER=1 FAIL_RESTART_RESTORE=1 STATBUS_ENV_CONFIG="$EXPECTED_CONFIG" STATBUS_USERS_FILE="$EXPECTED_USERS" \
    bash "$ROOT/install.sh" --channel prerelease --non-interactive > "$TMP_ROOT/stale-channel-failed-output" 2>&1
rc=$?
set -e
[ "$rc" = 78 ] || { cat "$TMP_ROOT/stale-channel-failed-output" >&2; exit 1; }
grep -Fq 'bash -s -- --channel prerelease --non-interactive' "$TMP_ROOT/stale-channel-failed-output"
echo 'PASS: failed stale restart restoration keeps the selected release and answers'
# A live holder must get an immediate plain refusal, without bootstrap mutation.
printf '{"trigger":"restart","restart":{"profile":"all"}}\n' > "$HOME/statbus/tmp/upgrade-in-progress.json"
perl -MFcntl=:flock -e 'open(my $f, "+<", $ARGV[0]) or die $!; flock($f, LOCK_EX) or die $!; print "locked\n"; sleep 8' \
    "$HOME/statbus/tmp/upgrade-in-progress.json" > "$TMP_ROOT/holder-ready" &
holder=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP_ROOT/holder-ready" ] && break; sleep 0.1; done
set +e
STATBUS_ENV_CONFIG="$EXPECTED_CONFIG" STATBUS_USERS_FILE="$EXPECTED_USERS" \
    bash "$ROOT/install.sh" --version v2026.09.0-rc.02 --non-interactive > "$TMP_ROOT/live-restart-output" 2>&1
rc=$?
set -e
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true
[ "$rc" = 78 ] || { cat "$TMP_ROOT/live-restart-output" >&2; exit 1; }
grep -q 'a restart is still running' "$TMP_ROOT/live-restart-output"
grep -Fq '"trigger":"restart"' "$HOME/statbus/tmp/upgrade-in-progress.json"
rm "$HOME/statbus/tmp/upgrade-in-progress.json"
echo 'PASS: live restart refuses without waiting or replacing intent'
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
grep -Fq 'bash -s -- --version v2026.09.0-rc.02 --non-interactive' "$TMP_ROOT/output"
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

for advice in \
    'port 80 is in use by apache2. sudo systemctl disable --now apache2. Your answers are saved. Then run the same install command again: curl -fsSL https://statbus.org/install.sh | bash' \
    'Only 12 GB free on /var/lib/docker. StatBus needs at least 20 GB to install. Free some space, then run the same install command again: curl -fsSL https://statbus.org/install.sh | bash' \
    'a restart is still running, or its services could not be restored. Wait for it to finish, then run the same install command again: curl -fsSL https://statbus.org/install.sh | bash'; do
    set +e
    printf '' | EXPECT_STDIN=pipe PIPE_MESSAGE="$advice" python3 -c \
        'import os, sys; os.setsid(); os.execv("/bin/bash", ["bash", sys.argv[1], "--version", "v2026.09.0-rc.02"])' \
        "$ROOT/install.sh" > "$TMP_ROOT/advice-output" 2>&1
    rc=$?
    set -e
    [ "$rc" = 78 ] || { echo "FAIL: actionable preflight became $rc"; exit 1; }
    grep -Fxq "$advice" "$TMP_ROOT/advice-output" || { cat "$TMP_ROOT/advice-output" >&2; exit 1; }
    ! grep -Eq 'SYSTEM UNUSABLE|INVARIANT|panic:' "$TMP_ROOT/advice-output"
done
echo 'PASS: port, disk, and restart remedies reach operator without internal diagnostics'

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
