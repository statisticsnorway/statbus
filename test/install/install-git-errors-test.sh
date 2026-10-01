#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin"
(
    cd "$REPO_ROOT/cli"
    commit=$(git rev-parse HEAD)
    go build -ldflags "-X github.com/statisticsnorway/statbus/cli/cmd.commit=$commit" -o "$tmpdir/sb" .
)

cat > "$tmpdir/bin/git" <<'FAKE_GIT'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" != statbus-install-test-git-error ]; then
    exec /usr/bin/git "$@"
fi
case "${2:-}" in
    authentication)
        echo "fatal: Authentication failed for 'https://operator:fixture-auth-secret@github.example/statbus.git/'" >&2
        ;;
    missing-ref)
        echo "fatal: couldn't find remote ref fixture-missing-ref" >&2
        ;;
    network)
        echo "fatal: unable to access 'https://operator:fixture-network-secret@does-not-resolve.invalid/statbus.git/': Could not resolve host: does-not-resolve.invalid" >&2
        ;;
    *)
        echo "unexpected fixture mode: ${2:-}" >&2
        ;;
esac
exit 1
FAKE_GIT
chmod +x "$tmpdir/bin/git"
export PATH="$tmpdir/bin:$PATH"

assert_contains() {
    local file="$1" text="$2" name="$3"
    if ! grep -Fq "$text" "$file"; then
        echo "FAIL: $name: '$text' not found in $file" >&2
        cat "$file" >&2
        exit 1
    fi
}

assert_absent() {
    local file="$1" text="$2" name="$3"
    if grep -Fq "$text" "$file"; then
        echo "FAIL: $name: secret '$text' survived in $file" >&2
        cat "$file" >&2
        exit 1
    fi
}

run_case() {
    local mode="$1" message="$2" secret="${3:-}"
    local terminal="$tmpdir/$mode.terminal" install_log="$tmpdir/$mode.install.log"
    set +e
    (cd "$REPO_ROOT" && STATBUS_INJECT_AT=preswap-fetch-returns-error STATBUS_INSTALL_TEST_GIT_ERROR="$mode" "$tmpdir/sb" install) 2>&1 | tee "$terminal" > "$install_log"
    local rc=${PIPESTATUS[0]}
    set -e
    if [ "$rc" -eq 0 ]; then
        echo "FAIL: $mode Git failure unexpectedly passed" >&2
        exit 1
    fi
    for surface in "$terminal" "$install_log"; do
        assert_contains "$surface" "$message" "$mode preserves Git diagnostic"
        if [ -n "$secret" ]; then
            assert_contains "$surface" "[REDACTED]" "$mode marks redaction"
            assert_absent "$surface" "$secret" "$mode redacts fixture secret"
        fi
    done
    echo "PASS: $mode Git diagnostic is actionable and redacted"
}

run_case authentication "fatal: Authentication failed" fixture-auth-secret
run_case missing-ref "fatal: couldn't find remote ref fixture-missing-ref"
run_case network "Could not resolve host" fixture-network-secret

echo "install Git error tests: PASS"
