#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/install.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

export HOME="$tmpdir/home"
export TRACE="$tmpdir/git.trace"
export SB_CALL_COUNT="$tmpdir/sb.count"
mkdir -p "$HOME/statbus/.git" "$tmpdir/bin"

# Simulate rc.18's installed binary: repo-fetch exists, but --tags is rejected
# by Cobra as EX_USAGE. Any bootstrap dependency on this box binary is a bug.
cat > "$HOME/statbus/sb" <<'OLD_SB'
#!/bin/bash
set -euo pipefail
count=0
[ -f "$SB_CALL_COUNT" ] && count=$(cat "$SB_CALL_COUNT")
printf '%s\n' "$((count + 1))" > "$SB_CALL_COUNT"
for arg in "$@"; do
    if [ "$arg" = --tags ]; then
        echo 'Error: unknown flag: --tags' >&2
        exit 64
    fi
done
echo "unexpected old sb invocation: $*" >&2
exit 65
OLD_SB

cat > "$tmpdir/bin/git" <<'FAKE_GIT'
#!/bin/bash
set -euo pipefail
[ "${GIT_TERMINAL_PROMPT:-}" = 0 ]
[ "${GIT_SSH_COMMAND:-}" = fixture-ssh-command ]
printf '%s\n' "$*" >> "$TRACE"
[ "$*" = "-C $HOME/statbus fetch origin --tags" ] || {
    echo "unexpected git invocation: $*" >&2
    exit 65
}
FAKE_GIT

for command_name in docker curl; do
    cat > "$tmpdir/bin/$command_name" <<'NOOP'
#!/bin/bash
exit 0
NOOP
done
cat > "$tmpdir/bin/statbus-install-test-usage-command" <<'USAGE_COMMAND'
#!/bin/bash
set -euo pipefail
count=0
[ -f "$SB_CALL_COUNT" ] && count=$(cat "$SB_CALL_COUNT")
printf '%s\n' "$((count + 1))" > "$SB_CALL_COUNT"
exit 64
USAGE_COMMAND
chmod +x "$HOME/statbus/sb" "$tmpdir/bin/"*
export PATH="$tmpdir/bin:$PATH"
export GIT_NETWORK_RETRY_DELAY_S=0
export GIT_SSH_COMMAND=fixture-ssh-command

if ! STATBUS_INSTALL_TEST_GIT_FETCH=tags bash "$INSTALLER" >"$tmpdir/tags.out" 2>&1; then
    echo 'FAIL: tag fetch did not fall back to compatibility-safe plain git' >&2
    cat "$tmpdir/tags.out" >&2
    exit 1
fi
grep -Fxq -- "-C $HOME/statbus fetch origin --tags" "$TRACE" || {
    echo 'FAIL: plain git did not fetch tags' >&2
    cat "$TRACE" >&2
    exit 1
}
[ ! -e "$SB_CALL_COUNT" ] || {
    echo 'FAIL: tag fetch invoked the old box binary' >&2
    cat "$tmpdir/tags.out" >&2
    exit 1
}
echo 'PASS: old box binary is bypassed and plain git fetches tags'

rm -f "$SB_CALL_COUNT"
set +e
STATBUS_INSTALL_TEST_GIT_FETCH=usage bash "$INSTALLER" >"$tmpdir/usage.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 64 ] || {
    echo "FAIL: usage error exited $rc, want 64" >&2
    cat "$tmpdir/usage.out" >&2
    exit 1
}
[ "$(cat "$SB_CALL_COUNT")" -eq 1 ] || {
    echo 'FAIL: usage error was retried' >&2
    cat "$tmpdir/usage.out" >&2
    exit 1
}
grep -Fq 'non-transient usage error' "$tmpdir/usage.out" || {
    echo 'FAIL: usage error was not named as non-transient' >&2
    cat "$tmpdir/usage.out" >&2
    exit 1
}
echo 'PASS: rc=64 usage error fails fast without retry'

echo 'install git-fetch compatibility tests: PASS'
