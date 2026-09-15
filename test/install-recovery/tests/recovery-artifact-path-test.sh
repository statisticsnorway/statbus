#!/bin/bash
# Ensure the actual failure-capture directory survives Actions upload globs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
python3 - "$ROOT" <<'PY'
from pathlib import Path
from fnmatch import fnmatchcase
import re
import sys
root = Path(sys.argv[1])
s = (root / '.github/workflows/install-recovery-harness.yaml').read_text()
block = s.split('name: install-recovery-log-${{ matrix.scenario }}', 1)[1].split('retention-days:', 1)[0]
patterns = re.findall(r'tmp/[^\n]+', block)
scenario = '1-boot-concurrent-install'
patterns = [p.replace('${{ matrix.scenario }}', scenario).strip() for p in patterns]
required = [
    f'tmp/install-recovery-{scenario}.log',
    f'tmp/statbus-recovery-{scenario}-64519724/registered/install-c10-first--install-c10-first.log',
    f'tmp/statbus-recovery-{scenario}-64519724/index.tsv',
    f'tmp/statbus-recovery-{scenario}-64519724/statbus-tmp/upgrade-progress.log',
]
for path in required:
    assert any(fnmatchcase(path, p) for p in patterns), f'upload omits {path}: {patterns}'
    print(f'PASS: uploads {path}')
assert not any(fnmatchcase('tmp/statbus-recovery-other-64519724/install.log', p) for p in patterns)
print('PASS: captured evidence stays scenario-scoped')
PY
