#!/bin/bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Test the actual Stage 0 verification helper without touching system apt files.
eval "$(sed -n '/^apt_http_sources() {$/,/^}$/p' "$REPO_ROOT/ops/setup-ubuntu-lts.sh")"
mkdir -p "$FIXTURE_DIR/sources.list.d"
printf 'URIs: https://mirror.example/ubuntu\n' > "$FIXTURE_DIR/sources.list.d/ubuntu.sources"
printf 'URIs: http://archive.ubuntu.com/ubuntu\n' > "$FIXTURE_DIR/sources.list.d/ubuntu.sources.bak"
printf 'deb http://ignored.example/ubuntu noble main\n' > "$FIXTURE_DIR/sources.list.d/ignored.disabled"

assert_clean() {
    if apt_http_sources "$FIXTURE_DIR/sources.list.d" "$FIXTURE_DIR/sources.list" >/dev/null; then
        echo 'FAIL: ignored backup or disabled file was treated as active' >&2
        exit 1
    fi
}
assert_detected() {
    if ! apt_http_sources "$FIXTURE_DIR/sources.list.d" "$FIXTURE_DIR/sources.list" >/dev/null; then
        echo 'FAIL: active HTTP apt source was missed' >&2
        exit 1
    fi
}

assert_clean
assert_clean # A rerun with an existing backup must remain green.
printf 'URIs: http://mirror.example/ubuntu\n' > "$FIXTURE_DIR/sources.list.d/extra.sources"
assert_detected
printf 'URIs: https://mirror.example/ubuntu\n' > "$FIXTURE_DIR/sources.list.d/extra.sources"
printf 'deb http://mirror.example/ubuntu noble main\n' > "$FIXTURE_DIR/sources.list.d/extra.list"
assert_detected
printf 'deb https://mirror.example/ubuntu noble main\n' > "$FIXTURE_DIR/sources.list.d/extra.list"
printf 'deb http://mirror.example/ubuntu noble main\n' > "$FIXTURE_DIR/sources.list"
assert_detected
printf 'deb https://mirror.example/ubuntu noble main\n' > "$FIXTURE_DIR/sources.list"
assert_clean

echo 'PASS: Stage 0 checks only apt-read sources and ignores backups on rerun'
