#!/bin/bash
# Real bootstrap location selection with a fully stubbed provider. Never creates a VM.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
python3 - "$ROOT" <<'PY'
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
script = r'''
export HCLOUD_TOKEN=offline-test-only GITHUB_RUN_ID=12345678
source "$ROOT/test/install-recovery/lib/vm-bootstrap.sh"
sleep() { echo sleep >> "$STATE/events"; }
_hcloud_server_ip() { echo '192.0.2.1'; }
_wait_for_ssh() { :; }
_apply_hardening() { :; }
hcloud() {
    local op="$2" previous='' location='' arg
    case "$op" in
      describe) return 1 ;;
      create)
        for arg in "$@"; do
            [ "$previous" != --location ] || location="$arg"
            previous="$arg"
        done
        printf '%s\n' "$location" >> "$STATE/locations"
        case "$CASE:$location" in
          fallback:fsn1|pin:fsn1) return 0 ;;
          fallback:*|all-fail:*)
            echo "hcloud: location $location: (resource_unavailable)" >&2
            return 1 ;;
          *) echo "UNEXPECTED create in $location for $CASE" >&2; return 99 ;;
        esac ;;
      *) echo "UNEXPECTED hcloud $*" >&2; return 99 ;;
    esac
}
if bootstrap_install_test_vm statbus-recovery-location v2026.09.0; then
    echo BOOTSTRAP_SUCCEEDED
else
    echo BOOTSTRAP_FAILED
fi
'''

cases = {
    'fallback': {
        'locations': 'hel1 fsn1 nbg1',
        'expected_calls': ['hel1', 'fsn1'],
        'expected_status': 'BOOTSTRAP_SUCCEEDED',
        'required_output': ['attempt 1/5 in hel1', 'attempt 1/5 in fsn1', 'succeeded in fsn1'],
        'expected_sleeps': 0,
    },
    'all-fail': {
        'locations': 'hel1 fsn1 nbg1',
        'expected_calls': ['hel1', 'fsn1', 'nbg1'] * 5,
        'expected_status': 'BOOTSTRAP_FAILED',
        'required_output': [
            'attempt 1/5 in hel1',
            'attempt 1/5 in fsn1',
            'attempt 1/5 in nbg1',
            'exhausted 5 attempts per location across (hel1 fsn1 nbg1)',
        ],
        'expected_sleeps': 4,
    },
    'pin': {
        'location': 'fsn1',
        'expected_calls': ['fsn1'],
        'expected_status': 'BOOTSTRAP_SUCCEEDED',
        'required_output': ['attempt 1/5 in fsn1', 'succeeded in fsn1'],
        'expected_sleeps': 0,
    },
}

failed = []
for case, expected in cases.items():
    with tempfile.TemporaryDirectory(prefix='location-fallback-', dir=root / 'tmp') as tmp:
        env = dict(os.environ, ROOT=str(root), STATE=tmp, CASE=case)
        env.pop('HCLOUD_LOCATION', None)
        env.pop('HCLOUD_LOCATIONS', None)
        if 'locations' in expected:
            env['HCLOUD_LOCATIONS'] = expected['locations']
        if 'location' in expected:
            env['HCLOUD_LOCATION'] = expected['location']
        result = subprocess.run(['bash', '-c', script], env=env, text=True, capture_output=True)
        state = Path(tmp)
        calls = (state / 'locations').read_text().splitlines() if (state / 'locations').exists() else []
        sleeps = (state / 'events').read_text().splitlines() if (state / 'events').exists() else []
        output = result.stdout + result.stderr
        good = (
            result.returncode == 0
            and expected['expected_status'] in result.stdout
            and calls == expected['expected_calls']
            and sleeps == ['sleep'] * expected['expected_sleeps']
            and all(text in output for text in expected['required_output'])
        )
        print(('PASS' if good else 'FAIL') + ': ' + case)
        if not good:
            failed.append(case)
            print(
                f"rc={result.returncode} calls={calls!r} sleeps={sleeps!r}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
if failed:
    raise SystemExit(f"{len(failed)} failed cases: {failed}")
PY
