#!/bin/bash
# Offline behavioral test of the real helper and its literal remote payload.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "${STALL_HELPER_UNDER_TEST:-$ROOT/test/install-recovery/lib/wedge-helpers.sh}"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-stall-probe.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
export TMP_ROOT
mkdir "$TMP_ROOT/bin"
export PATH="$TMP_ROOT/bin:$PATH"
cat > "$TMP_ROOT/bin/pgrep" <<'MOCK'
#!/bin/bash
# The pattern must match sb, but not the shell command containing itself.
[ "$1" = -f ] || exit 2
printf '%s\n' '/home/statbus/statbus/sb migrate up --verbose' | grep -Eq "$2" || exit 2
if printf '%s\n' "pgrep -f '$2'" | grep -Eq "$2"; then exit 2; fi
case "$CASE" in
 absent-pid) exit 1 ;;
 changing-pid) echo "$((424242 + $(cat "$TMP_ROOT/clock")))" ;;
 *) echo 424242 ;;
esac
MOCK
cat > "$TMP_ROOT/bin/ps" <<'MOCK'
#!/bin/bash
[ "$*" = '-o lstart= -p 424242' ] || [ "$CASE" = changing-pid ] || exit 2
case "$CASE" in
 missing-start) exit 1 ;;
 changing-start) printf '  start-%s\n' "$(cat "$TMP_ROOT/clock")" ;;
 *) echo '  Tue Sep 15 12:00:00 2026' ;;
esac
MOCK
chmod +x "$TMP_ROOT/bin/pgrep" "$TMP_ROOT/bin/ps"
# Model sudo -i's argument escaping for the old command-string path. This
# intentionally returns rc=0 with empty fields, as the actual local sudo
# reproduction did. It is a synthetic transport model, not SSH acceptance.
VM_EXEC() {
    if [ "${LEGACY_TRANSPORT:-sudo-model}" = direct ]; then "$@"; return; fi
    local command_string
    command_string=$(python3 - "$@" <<'PYMODEL'
import sys
print(' '.join(''.join(c if c.isascii() and (c.isalnum() or c in '_-$') else '\\' + c for c in arg) for arg in sys.argv[1:]))
PYMODEL
    )
    bash -c "$command_string"
}
VM_SCRIPT_INLINE() {
    local name=$1; shift
    cat > "$TMP_ROOT/$name.sh"
    case "$CASE" in
        transport-error) echo 'REL_PRESENT=1 MIGRATE_PID=424242 STARTED_AT=fake'; return 23 ;;
        malformed) echo 'REL_PRESENT= MIGRATE_PID= STARTED_AT='; return 0 ;;
        noisy) printf 'noise\nREL_PRESENT=1 MIGRATE_PID=424242 STARTED_AT=fake\n'; return 0 ;;
        slow) echo 30 > "$TMP_ROOT/clock" ;;
    esac
    # sudo -i joins argv without preserving empty arguments. Exercise the
    # real file-payload contract rather than Bash's richer local argv shape.
    local args=() arg
    for arg in "$@"; do [ -z "$arg" ] || args+=("$arg"); done
    bash "$TMP_ROOT/$name.sh" "${args[@]}"
}
date() { if [ "$1" = +%s ]; then cat "$TMP_ROOT/clock"; else command date "$@"; fi; }
sleep() { echo "$(( $(cat "$TMP_ROOT/clock") + $1 ))" > "$TMP_ROOT/clock"; }
run_case() {
    export CASE=$1
    echo 0 > "$TMP_ROOT/clock"
    local release="$TMP_ROOT/release-$CASE" output rc=0
    if [ "$CASE" != absent-release ]; then touch "$release"; fi
    output=$(wait_for_inject_stall_ready test-vm "$release" 18 2>"$TMP_ROOT/$CASE.stderr") || rc=$?
    if [ "$CASE" = stable ]; then
        [ "$rc" = 0 ] && [ "$output" = 424242 ] || { cat "$TMP_ROOT/$CASE.stderr"; exit 1; }
    else
        [ "$rc" != 0 ] && [ -z "$output" ] || { echo "FAIL $CASE: rc=$rc output=$output"; exit 1; }
    fi
    echo "PASS: $CASE"
}
for case_name in ${STALL_CASES:-stable absent-release absent-pid changing-pid changing-start missing-start transport-error malformed noisy slow}; do
    run_case "$case_name"
done
