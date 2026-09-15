#!/bin/bash
# Static guard: every detached/background VM launcher must log to a file and
# register that file with the shared harness manifest. No VM, Docker or DB.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$TEST_DIR/.." && pwd)"

python3 - "$HARNESS_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
files = sorted((root / "lib").glob("*.sh"))
files += sorted((root / "scenarios").glob("*.sh"))
files += sorted((root / "arcs").glob("*.sh"))
launch_re = re.compile(r"\b(?:tmux\s+new-session|nohup)\b")
background_re = re.compile(r"(?<!&)&\s*$")
log_write_re = re.compile(r">\s*(?:[\"']?)([^\s\"']*\.log)\b")
launch_output_re = re.compile(r">\s*(?:[\"']?)(?:[^\s\"']*\.log|\$[A-Za-z_][A-Za-z0-9_]*)")
failures = []
launches = []

for path in files:
    lines = path.read_text().splitlines()
    for index, line in enumerate(lines):
        if (not launch_re.search(line) and not background_re.search(line)) or line.lstrip().startswith("#"):
            continue
        launches.append(f"{path.relative_to(root)}:{index + 1}")
        if "arc_install_dispatch_with_inject" in line:
            helper = (root / "lib/arc-helpers.sh").read_text()
            if "harness_register_log arc-install-dispatch" not in helper:
                failures.append(f"{path.relative_to(root)}:{index + 1}: shared dispatch helper does not register its log")
            continue
        nearby = "\n".join(lines[max(0, index - 40):min(len(lines), index + 12)])
        if not launch_output_re.search(nearby):
            failures.append(f"{path.relative_to(root)}:{index + 1}: process launch has no .log redirection")
            continue
        if "harness_register_log" not in nearby:
            failures.append(f"{path.relative_to(root)}:{index + 1}: .log is not registered near its process launch")

# Foreground commands may also intentionally write scenario-owned logs. Guard
# all /tmp or variable .log redirections in scenarios/arcs, not just launch lines.
for directory in (root / "scenarios", root / "arcs"):
    for path in sorted(directory.glob("*.sh")):
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines):
            if line.lstrip().startswith("#") or not log_write_re.search(line):
                continue
            nearby = "\n".join(lines[max(0, index - 8):min(len(lines), index + 9)])
            if "harness_register_log" not in nearby:
                failures.append(f"{path.relative_to(root)}:{index + 1}: log redirection is not registered")

if failures:
    print("FAIL: unregistered harness process logs:", file=sys.stderr)
    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    sys.exit(1)

print("PASS: every tmux/nohup VM launch writes a registered log")
for launch in launches:
    print(f"  {launch}")
print("process log registration tests: PASS")
PY

# Exercise cleanup_vm's failure gate without sourcing credential/bootstrap code.
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-log-cleanup.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
sed -n '/^cleanup_vm() {$/,/^}$/p' "$HARNESS_DIR/lib/vm-bootstrap.sh" > "$TMP_ROOT/cleanup.sh"
# shellcheck disable=SC1090,SC1091 # extracted production helper
source "$TMP_ROOT/cleanup.sh"
_check_name_safety() { :; }
dump_stage_tmux_logs() { :; }
capture_failure_artifacts() { printf 'capture:%s\n' "$1" >> "$TMP_ROOT/trace"; }
hcloud() { :; }
# shellcheck disable=SC2034 # consumed dynamically by extracted cleanup_vm
VM_OWNED_BY_THIS_RUN=1 KEEP_VM=0 KEEP_VM_ON_FAILURE=0

# shellcheck disable=SC2034 # consumed dynamically by extracted cleanup_vm
rc=23
cleanup_vm statbus-recovery-test
grep -Fxq 'capture:statbus-recovery-test' "$TMP_ROOT/trace"
: > "$TMP_ROOT/trace"
# shellcheck disable=SC2034 # consumed dynamically by extracted cleanup_vm
rc=0
cleanup_vm statbus-recovery-test
[ ! -s "$TMP_ROOT/trace" ]
echo "PASS: cleanup captures non-zero scenario rc and skips success"
