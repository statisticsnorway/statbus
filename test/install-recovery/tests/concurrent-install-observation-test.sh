#!/bin/bash
# Exercise scenario observation gates without starting the scenario or a VM.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
python3 - "$ROOT" <<'PY'
from pathlib import Path
import subprocess
import sys
root = Path(sys.argv[1])
subprocess.run(['go', 'test', './cmd/', '-run', '^TestLiveInstallStateLogNamesHolder$', '-count=1'], cwd=root / 'cli', check=True)
print('PASS: live-install state line names holder, service line unchanged')
s = (root / 'test/install-recovery/scenarios/1-boot-concurrent-install.sh').read_text()
def check(label, code, success):
    p = subprocess.run(['bash', '-c', 'set -euo pipefail\n' + code], text=True, capture_output=True)
    if (p.returncode == 0) != success:
        raise AssertionError(f'{label}: rc={p.returncode}\n{p.stdout}\n{p.stderr}')
    print(f'PASS: {label}')
# Transport must fail even if it emits a plausible exit status. A malformed
# observation must never count as the expected nonzero product refusal.
a = s.index('if ! SECOND_EXIT=')
b = s.index('# Require the exact process ID', a)
gate = s[a:b]
for value, transport, success in [('1', 0, True), ('0', 0, False), ('?', 0, False), ('', 0, False), ('256', 0, False), ('1', 23, False)]:
    check(f'second exit={value!r} transport={transport}', f'''
SECOND_LOG=unused
VM_SCRIPT_INLINE() {{ cat >/dev/null; printf '%s\\n' '{value}'; return {transport}; }}
VM_EXEC() {{ echo 'live-upgrade'; }}
{gate}
''', success)
# Readiness failure with plausible stdout is still failure, not a valid PID.
a = s.index('if ! MIGRATE_PID=')
b = s.index('# The PID is diagnostic', a)
check('readiness rejects failed transport with PID stdout', '''
VM_NAME=unused RELEASE_FILE=unused STALL_MAX_WAIT_S=1 ip=unused
SSH_OPTS=()
ssh() { :; }
wait_for_inject_stall_ready() { echo 424242; return 23; }
''' + s[a:b], False)
a = s.index('FIRST_HOLDER=$(VM_EXEC')
b = s.index('# Phase 4', a)
for flag, success in [('{"holder":"install","pid":4242}', True), ('{"holder":"install"}', False), ('{"holder":"install","pid":0}', False), ('{"holder":"install","pid":"4242"}', False), ('{"holder":"service","pid":4242}', False), ('{"PID":123}', False), ('', False), ('{bad', False)]:
    check(f'holder flag {flag!r}', f"VM_EXEC() {{ printf '%s\\n' '{flag}'; }}\n" + s[a:b], success)
a = s.index('# Require the exact process ID')
b = s.index('# Phase 5', a)
valid = 'an installation started at 2026-09-25T07:00:00Z (process 4242) is still running'
for diagnostic, success in [(valid, True), ('holder PID=', False), ('Detected install state: crashed-upgrade', False), (valid.replace('an installation', 'an upgrade'), False), (valid.replace('4242', '4243'), False), (valid.replace(' (process 4242)', ''), False), (valid + '\nlsof tmp/upgrade-in-progress.json', False), (valid + '\nAn upgrade is already running', False)]:
    check(f'refusal diagnostic {diagnostic!r}', f"FIRST_PID=4242\nSECOND_OUTPUT='{diagnostic}'\n" + s[a:b], success)
a = s.index('echo "  first install exited: $FIRST_EXIT"')
b = s.index('# Phase 6', a)
for status, success in [('0', True), ('1', False), ('?', False)]:
    check(f'first exit {status!r}', f'FIRST_EXIT={status!r}\n' + s[a:b], success)

# Execute the exact identity selector against proc-shaped filesystem fixtures.
import tempfile
helper = (root / 'test/install-recovery/lib/wedge-helpers.sh').read_text()
identity_source = helper.split("<<'PY_IDENTITY'\n", 1)[1].split('\nPY_IDENTITY', 1)[0]
namespace = {'__name__': 'identity_test'}
exec(compile(identity_source, 'production-identity-selector', 'exec'), namespace)
for case in ['valid', 'missing-marker', 'wrong-env', 'wrong-ancestor', 'wrong-argv', 'missing-parent']:
    with tempfile.TemporaryDirectory() as tmp:
        fixture = Path(tmp)
        proc = fixture / 'proc'
        log, pid_file = fixture / 'install.log', fixture / 'install.pid'
        inject, release = 'concurrent-install-attempted-during-migrate-up', '/tmp/c10-release'
        log.write_text(f'INJECT: stalling at "{inject}" until {release} is removed')
        pid_file.write_text('100')
        for pid, parent in [(100, 1), (200, 1), (300, 100)]:
            base = proc / str(pid)
            base.mkdir(parents=True)
            (base / 'stat').write_text(f'{pid} (sb) S {parent} 0 0 0')
            (base / 'cmdline').write_bytes(b'/home/statbus/statbus/sb\0migrate\0up\0--verbose\0')
            (base / 'environ').write_bytes(b'')
        env = f'STATBUS_INJECT_AT={inject}\0STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE={release}\0'.encode()
        (proc / '300/environ').write_bytes(env)
        if case == 'missing-marker': log.write_text('still installing')
        if case == 'wrong-env': (proc / '300/environ').write_bytes(b'STATBUS_INJECT_AT=other\0')
        if case == 'wrong-ancestor': (proc / '300/stat').write_text('300 (sb) S 200 0 0 0')
        if case == 'wrong-argv': (proc / '300/cmdline').write_bytes(b'/bin/bash\0-c\0sb migrate up\0')
        if case == 'missing-parent': pid_file.write_text('999')
        found = namespace['select_pid'](log, pid_file, inject, release, proc, ['200', '300'])
        assert found == ('300' if case == 'valid' else ''), (case, found)
        print(f'PASS: injected migration identity {case}')

# The actual absence payload requires a readable directory, and its caller
# rejects transport errors rather than accepting a skipped observation.
a = s.index('if ! VM_SCRIPT_INLINE concurrent-flag-absent')
b = s.index('assert_health_passes', a)
for case in ['absent', 'present', 'missing-directory', 'transport-failed']:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        if case != 'missing-directory': (home / 'statbus/tmp').mkdir(parents=True)
        if case == 'present': (home / 'statbus/tmp/upgrade-in-progress.json').write_text('{}')
        function = 'VM_SCRIPT_INLINE() { cat >/dev/null; return 23; }' if case == 'transport-failed' else 'VM_SCRIPT_INLINE() { cat > "$HOME/probe.sh"; bash "$HOME/probe.sh"; }'
        check(f'flag absence {case}', f"export HOME='{home}'\n{function}\n" + s[a:b], case == 'absent')

# Exercise the actual EXIT body: failure capture must precede release, and
# its retained snapshot must survive cleanup's second capture.
trap_body = s.split("trap '\n", 1)[1].split("' EXIT", 1)[0]
with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp)
    (home / 'tmp/vm').mkdir(parents=True)
    (home / 'tmp/vm/index.tsv').write_text('pre-release evidence')
    trace = home / 'trace'
    code = f"""
HARNESS_ROOT='{home}' VM_NAME=vm RELEASE_FILE=unused VM_OWNED_BY_THIS_RUN=1
capture_failure_artifacts() {{ echo capture >> '{trace}'; }}
remove_release_file_in_vm() {{ echo release >> '{trace}'; }}
cleanup_vm() {{ echo cleanup >> '{trace}'; }}
trap '{trap_body}' EXIT
exit 1
"""
    subprocess.run(['bash', '-c', code], check=False)
    assert trace.read_text().splitlines() == ['capture', 'release', 'cleanup']
    assert len(list((home / 'tmp').glob('vm-pre-release-*/index.tsv'))) == 1
    print('PASS: failure snapshot retained before release and cleanup')

bootstrap = (root / 'test/install-recovery/lib/vm-bootstrap.sh').read_text()
a = bootstrap.index('statbus_uid=$(id -u statbus)')
b = bootstrap.index('# Read-only concurrency evidence', a)
for rc in [0, 23]:
    with tempfile.TemporaryDirectory() as tmp:
        code = f"""
capture_dir='{tmp}'
index="$capture_dir/index.tsv"
id() {{ echo 1000; }}
sudo() {{ printf '%s\\n' "$*"; return {rc}; }}
""" + bootstrap[a:b]
        check(f'user journal observation rc={rc}', code, True)
        text = (Path(tmp) / 'upgrade-unit-journal.txt').read_text()
        assert 'XDG_RUNTIME_DIR=/run/user/1000' in text and 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus' in text
        index = (Path(tmp) / 'index.tsv').read_text()
        assert index.startswith('captured\t' if rc == 0 else 'missing\t')

# Use the REAL cleanup function under errexit/ERR propagation. A diagnostic
# failure must neither replace the scenario's exit nor skip its owned deletion.
cleanup = bootstrap.split('cleanup_vm() {\n', 1)[1].split('\n}\n', 1)[0]
with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp)
    trace = home / 'trace'
    code = f"""
set -eE
trap 'rc=$?; echo ERROR >> "{trace}"' ERR
HARNESS_ROOT='{home}' VM_NAME=vm RELEASE_FILE=unused VM_OWNED_BY_THIS_RUN=1
capture_failure_artifacts() {{ echo capture >> '{trace}'; return 23; }}
remove_release_file_in_vm() {{ echo release >> '{trace}'; }}
_check_name_safety() {{ :; }}
dump_stage_tmux_logs() {{ echo stage >> '{trace}'; }}
hcloud() {{ echo delete >> '{trace}'; }}
cleanup_vm() {{
{cleanup}
}}
trap '{trap_body}' EXIT
exit 7
"""
    result = subprocess.run(['bash', '-c', code], capture_output=True, text=True)
    assert result.returncode == 7, (result.returncode, result.stdout, result.stderr)
    assert trace.read_text().splitlines() == ['capture', 'release', 'stage', 'capture', 'delete'], trace.read_text()
    print('PASS: real cleanup survives capture error and preserves original exit 7')

PY
