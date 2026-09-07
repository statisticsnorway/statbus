#!/bin/bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
source "$TEST_DIR/../lib/release-baseline.sh"

BOOTSTRAP="$TEST_DIR/../lib/vm-bootstrap.sh"

assert_eq() {
    local want="$1" got="$2" name="$3"
    if [ "$got" != "$want" ]; then
        echo "FAIL: $name: want '$want', got '$got'" >&2
        exit 1
    fi
    echo "PASS: $name -> $got"
}

got=$(printf '%s\n' \
    v2026.09.0-rc.03 \
    v2026.08.1 \
    v2026.08.1-rc.01 \
    v2026.08.0 \
    | select_release_baseline_from_tags v2026.09.0-rc.04)
assert_eq v2026.08.1 "$got" "stable is preferred over a newer RC"

got=$(printf '%s\n' \
    v2026.01.0-rc.01 \
    v2026.01.0-rc.02 \
    v2025.12.9-beta.1 \
    | select_release_baseline_from_tags v2026.01.0-rc.03)
assert_eq v2026.01.0-rc.02 "$got" "newest RC is the no-stable fallback"

got=$(printf '%s\n' \
    v2026.09.0 \
    v2026.09.0-rc.04 \
    v2026.08.1 \
    | select_release_baseline_from_tags v2026.09.0-rc.04)
assert_eq v2026.08.1 "$got" "target and future tags are strictly excluded"

# Required local dry sanity against the repository's real tag ledger.
got=$(select_release_baseline_from_repo "$REPO_ROOT" v2026.09.0-rc.04)
assert_eq v2026.08.1 "$got" "real ledger for v2026.09.0-rc.04"

# STATBUS-341: the recovery credential file is private from its first inode and
# remains private after upload. Pin the security contract locally without ever
# supplying or printing a token value.
grep -Fq 'env_config_file=$(umask 077; mktemp)' "$BOOTSTRAP" || {
    echo "FAIL: vm env-config must be created under umask 077" >&2
    exit 1
}
grep -Fq "'chmod 0600 /tmp/env-config'" "$BOOTSTRAP" || {
    echo "FAIL: uploaded /tmp/env-config must remain mode 0600" >&2
    exit 1
}
if grep -Fq "'chmod 0644 /tmp/env-config'" "$BOOTSTRAP"; then
    echo "FAIL: vm env-config permissions must never be widened to 0644" >&2
    exit 1
fi
mode_probe=$(umask 077; mktemp)
mode=$(stat -f '%Sp' "$mode_probe" 2>/dev/null || stat -c '%A' "$mode_probe")
rm -f "$mode_probe"
assert_eq -rw------- "$mode" "token-bearing tempfile creation mode"

echo "release-baseline tests: PASS"
