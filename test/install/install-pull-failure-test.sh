#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/install.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_eq() {
    local want="$1" got="$2" name="$3"
    if [ "$got" != "$want" ]; then
        echo "FAIL: $name: want '$want', got '$got'" >&2
        exit 1
    fi
    echo "PASS: $name -> $got"
}

assert_contains() {
    local file="$1" text="$2" name="$3"
    if ! grep -F "$text" "$file" >/dev/null; then
        echo "FAIL: $name: '$text' not found" >&2
        cat "$file" >&2
        exit 1
    fi
    echo "PASS: $name"
}

assert_eq auth "$(printf '%s\n' 'denied: authentication required (HTTP 403)' | STATBUS_INSTALL_TEST_CLASSIFY_PULL=1 bash "$INSTALLER")" "auth classification"
assert_eq missing "$(printf '%s\n' 'manifest unknown: not found' | STATBUS_INSTALL_TEST_CLASSIFY_PULL=1 bash "$INSTALLER")" "missing classification"
assert_eq network "$(printf '%s\n' 'dial tcp: i/o timeout' | STATBUS_INSTALL_TEST_CLASSIFY_PULL=1 bash "$INSTALLER")" "network classification"

cat > "$tmpdir/docker" <<'FAKE_DOCKER'
#!/bin/bash
set -euo pipefail
count=0
[ -f "$FAKE_DOCKER_COUNT" ] && count=$(cat "$FAKE_DOCKER_COUNT")
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_DOCKER_COUNT"
case "${FAKE_DOCKER_MODE:-auth}" in
    network-then-success)
        if [ "$count" -lt 3 ]; then
            echo "dial tcp: i/o timeout" >&2
            exit 1
        fi
        echo "pulled"
        ;;
    missing)
        echo "manifest unknown: not found" >&2
        exit 1
        ;;
    auth)
        echo "denied: requested access to the resource is denied (HTTP 403)" >&2
        exit 1
        ;;
esac
FAKE_DOCKER
chmod +x "$tmpdir/docker"
export PATH="$tmpdir:$PATH"
export FAKE_DOCKER_COUNT="$tmpdir/count"
export STATBUS_INSTALL_TEST_PULL_IMAGE=ghcr.io/statisticsnorway/statbus-sb:deadbeef
export DOCKER_PULL_RETRY_DELAY_S=0

rm -f "$FAKE_DOCKER_COUNT"
FAKE_DOCKER_MODE=network-then-success bash "$INSTALLER" >"$tmpdir/retry.out" 2>&1
assert_eq 3 "$(cat "$FAKE_DOCKER_COUNT")" "network failure retries until success"
assert_contains "$tmpdir/retry.out" "failed [network]" "network retry is visibly classified"

rm -f "$FAKE_DOCKER_COUNT"
if FAKE_DOCKER_MODE=auth bash "$INSTALLER" >"$tmpdir/auth.out" 2>&1; then
    echo "FAIL: auth-denied pull unexpectedly passed" >&2
    exit 1
fi
assert_eq 3 "$(cat "$FAKE_DOCKER_COUNT")" "auth failure receives bounded retries"
assert_contains "$tmpdir/auth.out" "pull failed [auth]" "auth failure class is preserved"
assert_contains "$tmpdir/auth.out" "Package settings -> Change visibility -> Public" "auth failure names visibility remedy"
assert_contains "$tmpdir/auth.out" "denied: requested access" "raw Docker failure is preserved"

rm -f "$FAKE_DOCKER_COUNT"
if FAKE_DOCKER_MODE=missing bash "$INSTALLER" >"$tmpdir/missing.out" 2>&1; then
    echo "FAIL: missing pull unexpectedly passed" >&2
    exit 1
fi
assert_eq 3 "$(cat "$FAKE_DOCKER_COUNT")" "missing failure receives bounded retries"
assert_contains "$tmpdir/missing.out" "pull failed [missing]" "missing failure class is preserved"

echo "install pull failure tests: PASS"
