#!/usr/bin/env bash
# Offline catalog-selection contract. Never contacts the LXD host.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"
current=v2026.09.3-rc.05
names=$(cat <<'NAMES'
fleet-base-v2026-09-3-rc-05
fleet-base-v2026-09-3-rc-05-hardened-nothing-installed
s2-base-v2026-09-3-rc-05-installed-v2026-09-2-standalone
s2-base-v2026-09-3-rc-05-hardened-nothing-installed
fleet-base-v2026-09-3-rc-04
fleet-base-v2026-09-3-rc-04-installed-v2026-09-2-standalone
s2-base-v2026-09-3-rc-04-hardened-nothing-installed
s2-base-v2026-09-3-rc-04-installed-v2026-09-2-standalone
s2-base-vmanual
fleet-base-foo
fleet-base-v2026-09-3-rc-04evil
s2-base-v2026-09-3-rc-04evil-installed-v2026-09-2-standalone
s2-v2026-09-3-rc-04-scenario
other-instance
NAMES
)
expected=$(cat <<'EXPECTED'
fleet-base-v2026-09-3-rc-04
fleet-base-v2026-09-3-rc-04-installed-v2026-09-2-standalone
s2-base-v2026-09-3-rc-04-hardened-nothing-installed
s2-base-v2026-09-3-rc-04-installed-v2026-09-2-standalone
EXPECTED
)
actual=$(_lxd_bases_to_prune "$current" <<< "$names")
[ "$actual" = "$expected" ] || {
    printf 'FAIL: prune selector\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    exit 1
}
if _lxd_bases_to_prune 'vmanual' <<< "$names" >/dev/null; then
    echo 'FAIL: invalid candidate tag accepted' >&2
    exit 1
fi
echo 'PASS: LXD prune selects only other valid candidate bases and preserves current checkpoints'
