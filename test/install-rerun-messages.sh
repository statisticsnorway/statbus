#!/usr/bin/env bash
# Scan operator-facing retry instructions, excluding comments and usage examples.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
paths = ['install.sh', 'cli/cmd/install.go', 'cli/cmd/root.go', 'cli/internal/diskpolicy/policy.go', 'cli/internal/unitfloor/unitfloor.go']
retry = re.compile(r'(?i)(re.?run|run the same install|run the installer again|then run|to verify|switch to that user|retry)')
found = 0
for path in paths:
    for number, line in enumerate((root / path).read_text().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith(('#', '//')) or not retry.search(line):
            continue
        if path == 'install.sh' and stripped.startswith("STATBUS_INSTALL_RERUN_COMMAND='"):
            continue
        if './sb install' in line and ('"' in line or "'" in line) and not stripped.startswith(('//', '#')):
            # A comment on a code line is not itself a user-facing instruction.
            if line.split('//', 1)[0].count('"') < 2 and 'fmt.' not in line:
                continue
            raise SystemExit(f'{path}:{number}: directory-dependent retry: {line}')
        if 'curl -fsSL https://statbus.org/install.sh | bash' in line and 'usage' not in line.lower():
            if '  curl -fsSL https://statbus.org/install.sh | bash`' not in line:
                raise SystemExit(f'{path}:{number}: hardcoded retry: {line}')
        if 'RerunCommand()' in line or '$STATBUS_INSTALL_RERUN_COMMAND' in line:
            found += 1
assert found >= 15, f'only {found} rerun references scanned'
shell = (root / 'install.sh').read_text()
assert "STATBUS_INSTALL_RERUN_COMMAND='curl -fsSL https://statbus.org/install.sh | bash'" in shell
assert 'export STATBUS_INSTALL_RERUN_COMMAND' in shell
policy = (root / 'cli/internal/diskpolicy/policy.go').read_text()
assert 'os.Getenv("STATBUS_INSTALL_RERUN_COMMAND")' in policy
print(f'PASS: scanned {found} saved-command retry references')
PY
