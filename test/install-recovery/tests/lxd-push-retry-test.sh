#!/usr/bin/env bash
# Offline contract for _lxd_push. Never contacts the LXD host: _lxd_host is
# replaced after sourcing with a stub that replays scripted outcomes.
# Race text is the verbatim error from rc.15 LXD run 36433435451.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
# LXD_BACKEND_SOURCE lets a mutated copy be supplied for mutation checking.
# shellcheck disable=SC1090
source "${LXD_BACKEND_SOURCE:-$ROOT/test/install-recovery/lib/lxd-backend.sh}"
set +e
fail() { echo "FAIL: $*" >&2; exit 1; }

RACE='Error: error receiving version packet from server: error reading packet length: 0 of 4: read unix @->/proc/self/fd/46/forkfile.sock: read: connection reset by peer'
OTHER='Error: Not Found'
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lxd-push-test.XXXXXX")
trap 'rm -rf "$STUB_DIR"' EXIT
sleep() { :; }

# Each call consumes the next scripted outcome: "ok" or an error message.
_lxd_host() {
    local n outcome
    n=$(( $(cat "$STUB_DIR/calls") + 1 ))
    echo "$n" > "$STUB_DIR/calls"
    printf '%s\n' "$*" >> "$STUB_DIR/argv"
    outcome=$(sed -n "${n}p" "$STUB_DIR/script")
    [ "$outcome" = ok ] && return 0
    printf '%s\n' "$outcome" >&2
    return 1
}
run_case() {
    printf '%s\n' "$@" > "$STUB_DIR/script"
    echo 0 > "$STUB_DIR/calls"
    : > "$STUB_DIR/argv"
    _lxd_push /root/src inst/tmp/dest 2>"$STUB_DIR/stderr"
}
calls() { cat "$STUB_DIR/calls"; }

run_case ok;                           rc=$?
[ "$rc" = 0 ] && [ "$(calls)" = 1 ] || fail "clean push: rc=$rc calls=$(calls)"
[ "$(cat "$STUB_DIR/argv")" = 'lxc file push /root/src inst/tmp/dest' ] || fail "argv not forwarded: $(cat "$STUB_DIR/argv")"

run_case "$RACE" ok;                   rc=$?
[ "$rc" = 0 ] && [ "$(calls)" = 2 ] || fail "race then ok: rc=$rc calls=$(calls)"
grep -q 'forkfile idle-exit race (attempt 1/3)' "$STUB_DIR/stderr" || fail 'race retry not announced'

run_case "$OTHER" ok;                  rc=$?
[ "$rc" = 1 ] && [ "$(calls)" = 1 ] || fail "non-race error must not retry: rc=$rc calls=$(calls)"
grep -qF "$OTHER" "$STUB_DIR/stderr" || fail 'non-race error text not surfaced'

run_case "$RACE" "$RACE" "$RACE" ok;  rc=$?
[ "$rc" = 1 ] && [ "$(calls)" = 3 ] || fail "persistent race must stop at 3: rc=$rc calls=$(calls)"

echo 'PASS: lxd push retries only the forkfile idle-exit race, at most 3 attempts'
