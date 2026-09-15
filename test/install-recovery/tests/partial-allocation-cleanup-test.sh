#!/bin/bash
# Real bootstrap and cleanup, fully mocked provider. Never executes hcloud/SSH.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
python3 - "$ROOT" <<'PY'
from pathlib import Path
import os, subprocess, sys, tempfile
root = Path(sys.argv[1])
script = r'''
export HCLOUD_TOKEN=offline-test-only GITHUB_RUN_ID=12345678
source "${BOOTSTRAP:-$ROOT/test/install-recovery/lib/vm-bootstrap.sh}"
# Block every non-provider side effect too.
ssh() { echo 'UNEXPECTED SSH' >&2; return 99; }
sleep() { echo sleep >> "$STATE/events"; }
dump_stage_tmux_logs() { echo diagnostics >> "$STATE/events"; }
capture_failure_artifacts() { echo diagnostics >> "$STATE/events"; }
_hcloud_server_ip() { echo '192.0.2.1'; }
_wait_for_ssh() { echo ssh-ready >> "$STATE/events"; }
_apply_hardening() { echo hardening >> "$STATE/events"; }
hcloud() {
    printf '%s\n' "$*" >> "$STATE/calls"
    local op="$2" name="${3:-}" token='' previous='' arg
    case "$op" in
      create)
        for arg in "$@"; do
          [ "$previous" != --name ] || name="$arg"
          [ "$previous" != --label ] || token="${arg#statbus-create-token=}"
          previous="$arg"
        done
        if [ "$CASE" = capacity ]; then
            echo 'hcloud: (resource_unavailable)' >&2
            return 1
        fi
        printf '%s\n' "$name" > "$STATE/name"
        printf '%s\n' "$token" > "$STATE/token"
        touch "$STATE/allocated"
        if [ "$CASE" = success ]; then return 0; fi
        echo 'Waiting for create_server (server: 166053156) ... done' >&2
        echo 'Waiting for start_server (server: 166053156) ...' >&2
        if [ "$CASE" = capacity-partial ]; then
            echo 'hcloud: (resource_unavailable)' >&2
        else
            echo 'hcloud: (server_error)' >&2
        fi
        return 1 ;;
      describe)
        if [ "$CASE" = preexisting ] && [ ! -f "$STATE/allocated" ]; then return 0; fi
        [ -f "$STATE/allocated" ] || return 1
        [ "$CASE" != lookup-failed ] || { echo 'unavailable' >&2; return 1; }
        token=$(cat "$STATE/token")
        [ "$CASE" != foreign ] || token=another-run
        [ "$CASE" != missing-label ] || token=''
        [ "$CASE" != malformed ] || { echo invalid-output; return 0; }
        local id=166053156 found_name
        found_name=$(cat "$STATE/name")
        [ "$CASE" != wrong-name ] || found_name=statbus-recovery-other-12345678
        [ "$CASE" != invalid-id ] || id=-10
        printf '%s %s %s\n' "$id" "$token" "$found_name"
        return 0 ;;
      delete)
        printf '%s\n' "$name" >> "$STATE/deletes"
        if [ "$CASE" = delete-failed ]; then echo 'delete failed' >&2; return 1; fi
        return 0 ;;
      ip) echo 'UNEXPECTED IP LOOKUP' >&2; return 99 ;;
      *) echo "UNEXPECTED hcloud $*" >&2; return 99 ;;
    esac
}
if [ "$CASE" = exit-trap ]; then
    trap 'original_rc=$?; cleanup_vm "$VM_NAME" "$original_rc"; exit "$original_rc"' EXIT
    bootstrap_install_test_vm statbus-recovery-offline v2026.09.0
    exit 98
fi
if [ "$CASE" = success ]; then
    bootstrap_install_test_vm statbus-recovery-offline v2026.09.0
    [ "$VM_OWNED_BY_THIS_RUN" = 1 ]
    [ -z "${VM_PARTIAL_CREATE_ID:-}" ]
    cleanup_vm "$VM_NAME" 0
    exit 0
fi
if bootstrap_install_test_vm statbus-recovery-offline v2026.09.0; then
    echo 'bootstrap unexpectedly succeeded' >&2; exit 98
fi
cleanup_vm "$VM_NAME" 1
'''
cases = ['allocated-start-failed', 'preexisting', 'foreign', 'missing-label', 'wrong-name', 'invalid-id', 'malformed', 'lookup-failed', 'keep', 'keep-failure', 'delete-failed', 'exit-trap', 'capacity', 'capacity-partial', 'success']
failed = []
for case in cases:
    with tempfile.TemporaryDirectory(prefix='partial-create-', dir=root/'tmp') as tmp:
        env = dict(os.environ, ROOT=str(root), STATE=tmp, CASE=case, KEEP_VM='1' if case=='keep' else '0', KEEP_VM_ON_FAILURE='1' if case=='keep-failure' else '0')
        p = subprocess.run(['bash', '-c', script], env=env, text=True, capture_output=True)
        base = Path(tmp)
        deletes = (base/'deletes').read_text().splitlines() if (base/'deletes').exists() else []
        calls = (base/'calls').read_text()
        events = (base/'events').read_text() if (base/'events').exists() else ''
        want = ['166053156'] if case in ['allocated-start-failed', 'delete-failed', 'exit-trap', 'capacity-partial'] else []
        if case == 'success': want = ['statbus-recovery-offline-12345678']
        expected_events = 'sleep\n' * 4 if case == 'capacity' else 'ssh-ready\nhardening\ndiagnostics\n' if case == 'success' else ''
        expected_creates = 0 if case == 'preexisting' else 5 if case == 'capacity' else 1
        good = p.returncode == (1 if case == 'exit-trap' else 0) and deletes == want and events == expected_events and calls.count('server create') == expected_creates
        if case == 'delete-failed': good = good and 'delete failed' in p.stderr
        print(('PASS' if good else 'FAIL') + ': ' + case)
        if not good:
            failed.append(case)
            print(f'rc={p.returncode} deletes={deletes!r} expected={want!r} events={events!r}\n{p.stdout}{p.stderr}\n{calls}')
if failed: raise SystemExit(f'{len(failed)} failed cases: {failed}')
PY
