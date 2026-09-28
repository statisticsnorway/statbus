#!/bin/bash
# Offline fixture regression for STATBUS-361: a BASE_SHA determines where the
# token lives. Calls the production renderer, not a copy of its era logic.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-token-era.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
# GNU first: on Linux, `stat -f` means --file-system and succeeds, printing
# filesystem status instead of a mode, so a BSD-first probe never falls back.
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

export HCLOUD_TOKEN=dummy-hcloud-token
# vm-bootstrap.sh derives HARNESS_ROOT from its actual location and does not
# touch a VM when sourced. Allow a mutated copy to be supplied for mutation
# checking without changing the test's assertions or its git history.
# shellcheck disable=SC1090
source "${HARNESS_BOOTSTRAP_SOURCE:-$ROOT/test/install-recovery/lib/vm-bootstrap.sh}"
# Used by the sourced renderer, which ShellCheck cannot follow dynamically.
# shellcheck disable=SC2034
HARNESS_ROOT=$ROOT

render() {
    local base="$1" config="$TMP_ROOT/$2.config" credentials="$TMP_ROOT/$2.credentials"
    BASE_SHA="$base"
    (umask 077; printf 'DEPLOYMENT_SLOT_CODE=test\n' > "$config"; : > "$credentials")
    harness_render_github_token "$config" "$credentials"
    [ "$(file_mode "$config")" = 600 ] || fail "config permissions for $base"
    [ "$(file_mode "$credentials")" = 600 ] || fail "credentials permissions for $base"
}

export GITHUB_TOKEN=dummy-arc-token-not-a-secret
render 626bc0d9b post361
[ "$(cat "$TMP_ROOT/post361.config")" = 'DEPLOYMENT_SLOT_CODE=test' ] || fail 'post-361 token leaked into config'
[ "$(cat "$TMP_ROOT/post361.credentials")" = 'GITHUB_TOKEN=dummy-arc-token-not-a-secret' ] || fail 'post-361 credentials lack token'
render '' current
[ "$(cat "$TMP_ROOT/current.config")" = 'DEPLOYMENT_SLOT_CODE=test' ] || fail 'unset BASE_SHA must use current-era config'
[ "$(cat "$TMP_ROOT/current.credentials")" = 'GITHUB_TOKEN=dummy-arc-token-not-a-secret' ] || fail 'unset BASE_SHA must use current-era credentials'

render '626bc0d9b^' boundary-before
[ "$(tail -n 1 "$TMP_ROOT/boundary-before.config")" = 'GITHUB_TOKEN=dummy-arc-token-not-a-secret' ] || fail 'parent of 361 must keep legacy placement'
[ ! -s "$TMP_ROOT/boundary-before.credentials" ] || fail 'parent of 361 must not carry credentials token'
render 730b5001c pre361
[ "$(cat "$TMP_ROOT/pre361.config")" = $'DEPLOYMENT_SLOT_CODE=test\nGITHUB_TOKEN=dummy-arc-token-not-a-secret' ] || fail 'pre-361 config lacks token'
[ ! -s "$TMP_ROOT/pre361.credentials" ] || fail 'pre-361 credentials incorrectly contain token'

render d53731ec5 schema-floor
[ "$(tail -n 1 "$TMP_ROOT/schema-floor.config")" = 'GITHUB_TOKEN=dummy-arc-token-not-a-secret' ] || fail 'schema-floor base must keep legacy token placement'
[ ! -s "$TMP_ROOT/schema-floor.credentials" ] || fail 'schema-floor credentials incorrectly contain token'

unset GITHUB_TOKEN
render 626bc0d9b anonymous
[ "$(cat "$TMP_ROOT/anonymous.config")" = 'DEPLOYMENT_SLOT_CODE=test' ] || fail 'anonymous config changed'
[ ! -s "$TMP_ROOT/anonymous.credentials" ] || fail 'anonymous credentials unexpectedly populated'

export GITHUB_TOKEN=dummy-arc-token-not-a-secret
if (export BASE_SHA=not-a-valid-base; harness_render_github_token "$TMP_ROOT/anonymous.config" "$TMP_ROOT/anonymous.credentials") 2>/dev/null; then
    fail 'invalid BASE_SHA must fail instead of silently choosing an era'
fi

echo 'PASS: token placement follows the post-361, pre-361 and anonymous BASE_SHA contracts'
