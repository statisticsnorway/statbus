#!/usr/bin/env bash
# Exercise the full public launcher with real tmux and a safe child entrypoint.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v tmux >/dev/null || { echo 'tmux is required' >&2; exit 1; }
TMUX_BINARY=$(command -v tmux)
mkdir -p "$ROOT/tmp"
FIXTURE=$(mktemp -d "$ROOT/tmp/dev-detached.XXXXXX")
# Keep the Unix socket path short on macOS, independent of checkout path length.
SOCKET_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sb578.XXXXXX")
export DETACHED_TEST_SOCKET="$SOCKET_DIR/socket" TMUX_BINARY
cleanup() {
    "$TMUX_BINARY" -S "$DETACHED_TEST_SOCKET" kill-server 2>/dev/null || true
    rm -f "$DETACHED_TEST_SOCKET"
    rmdir "$SOCKET_DIR" 2>/dev/null || true
}
trap cleanup EXIT
WORK="$FIXTURE/work space"
mkdir -p "$WORK/ops" "$WORK/cli" "$WORK/.db-seed" "$FIXTURE/bin"
cp "$ROOT/dev.sh" "$WORK/launcher.sh"
: > "$WORK/ops/dev-seed-restore.sh"
: > "$WORK/.db-seed/seed.pg_dump"
cat > "$WORK/sb" <<'SH'
#!/bin/bash
[[ "$*" == committed-drift ]]
SH
cat > "$WORK/dev.sh" <<'SH'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == detached ]]; then
    exec bash ./launcher.sh "$@"
fi
printf '%s\0' "$@" > child-args
status=$(cat expected-status)
echo "safe child finished: exit $status"
printf '%s\n' "$status" > child-exit
exit "$status"
SH
cat > "$FIXTURE/bin/tmux" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "$1" == -L && "$2" == statbus-dev ]]
shift 2
exec "$TMUX_BINARY" -S "$DETACHED_TEST_SOCKET" "$@"
SH
chmod +x "$WORK/sb" "$WORK/dev.sh" "$FIXTURE/bin/tmux"
git -C "$WORK" init -q
export PATH="$FIXTURE/bin:$PATH"
run_case() {
    local name=$1 status=$2
    shift 2
    rm -f "$WORK/child-args" "$WORK/child-exit"
    printf '%s\n' "$status" > "$WORK/expected-status"
    printf '%s\0' "$@" > "$WORK/expected-args"
    (cd "$WORK" && ./dev.sh detached "$@") > "$FIXTURE/$name-launch.log" 2>&1
    cat "$FIXTURE/$name-launch.log"
    local attempt
    for ((attempt=0; attempt<100; attempt++)); do
        [[ -f "$WORK/child-exit" ]] && break
        sleep 0.1
    done
    [[ -f "$WORK/child-exit" ]] || { echo "FAIL $name: child did not finish within 10 seconds ($FIXTURE)" >&2; return 1; }
    cmp "$WORK/expected-args" "$WORK/child-args"
    [[ "$(cat "$WORK/child-exit")" == "$status" ]]
    echo "PASS $name: exact child arguments and explicit child exit $status (launcher exit 0 is not child success)"
    # The production session name has second granularity. Stop this private
    # server between cases so each is independent even in the same second.
    "$TMUX_BINARY" -S "$DETACHED_TEST_SOCKET" kill-server 2>/dev/null || true
}
run_case advertised-fast 0 test fast
mv "$WORK" "$WORK's"
WORK="$WORK's"
run_case quoted-failure 23 test 'space argument' "single'quote" 'double"quote' '' '$HOME; touch forbidden' $'line\nbreak'
run_case single-command 0 help
echo "PASS detached public launcher acceptance with real tmux. Evidence: $FIXTURE"
