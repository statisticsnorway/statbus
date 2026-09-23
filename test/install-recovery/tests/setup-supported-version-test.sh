#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/ops/setup-ubuntu-lts.sh"
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# The production script uses associative arrays in unrelated account setup code,
# which macOS's Bash 3 cannot evaluate. Load the gate itself from the production
# file so this remains a behavior test of the real implementation without
# copying the function into the test.
eval "$(grep '^SUPPORTED_UBUNTU_VERSIONS=' "$SETUP_SCRIPT")"
log_error() {
    echo "[ERROR] $1" >&2
}
eval "$(sed -n '/^check_supported_os() {$/,/^}$/p' "$SETUP_SCRIPT")"

write_os_release() {
    local version_id="$1" codename="$2"
    cat > "$FIXTURE_DIR/os-release" <<EOF
ID=ubuntu
VERSION_ID="$version_id"
VERSION_CODENAME=$codename
EOF
}

assert_supported() {
    local version_id="$1" codename="$2"
    write_os_release "$version_id" "$codename"
    # Used by check_supported_os loaded through eval above.
    # shellcheck disable=SC2034
    OS_RELEASE_FILE="$FIXTURE_DIR/os-release"
    check_supported_os >/dev/null
}

assert_refused() {
    local version_id="$1" codename="$2" output
    write_os_release "$version_id" "$codename"
    # Used by check_supported_os loaded through eval above.
    # shellcheck disable=SC2034
    OS_RELEASE_FILE="$FIXTURE_DIR/os-release"
    if output=$(check_supported_os 2>&1); then
        echo "FAIL: Ubuntu $version_id was accepted" >&2
        exit 1
    fi
    grep -Fq "detected $version_id; supported versions: 24.04 26.04" <<< "$output" || {
        echo "FAIL: refusal did not name detected and supported versions: $output" >&2
        exit 1
    }
}

assert_supported 24.04 noble
assert_supported 26.04 resolute
assert_refused 22.04 jammy
assert_refused 25.10 questing

echo "PASS: setup supports Ubuntu 24.04 and 26.04 and refuses other releases"
