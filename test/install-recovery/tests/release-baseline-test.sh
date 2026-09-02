#!/bin/bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
source "$TEST_DIR/../lib/release-baseline.sh"

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

echo "release-baseline tests: PASS"
