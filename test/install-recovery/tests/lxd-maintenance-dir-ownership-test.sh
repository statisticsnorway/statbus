#!/usr/bin/env bash
# Offline regression for STATBUS-425 M3a (found LIVE, not offline: a real
# un-park-to-completion-arc.sh run through this exact code path failed
# "write maintenance flag .../statbus-maintenance/active: permission
# denied" — see the progress log's un-park section for the full trace).
#
# ROOT CAUSE: three remote-script blocks in lxd-backend.sh pre-copy a
# ready-made .env.config onto a freshly cloned checkout before running
# `./sb install`/statbus-install.sh. That makes install.go's checkConfigDone
# (".env.config exists") return true on the VERY FIRST pass, so its
# "Configuration" step (runCreateConfig — the ONLY code that os.MkdirAll()s
# ~/statbus-maintenance and ~/statbus-backups, running AS the statbus user)
# never executes. Docker's own bind-mount auto-create then creates the still-
# missing ~/statbus-maintenance directory as ROOT (the Docker daemon's own
# uid) the moment `docker compose up` runs in the "Services" step — so the
# upgrade daemon (runs as statbus) can never write the maintenance flag into
# it. The Hetzner VM harness never hits this: its own install_statbus_at_sha
# supplies an ANSWER file (STATBUS_ENV_CONFIG) the installer's prompts
# consume, never a pre-existing .env.config the Configuration step's own
# check would see. This is a harness-only workaround, not a product fix —
# the underlying installer gap (only runCreateConfig ever creates these two
# directories, so ANY path that supplies a pre-existing .env.config skips
# them) is filed as STATBUS-431; keep this mkdir here until that lands.
#
# STATBUS-425 M3b review round R2 (found by review): the original version of
# this test bounded each copy site's "own block" by walking backward to the
# nearest line matching /<<'?REMOTE'?\s*$/ — but EVERY real VM_SCRIPT_INLINE
# call in this file has trailing content after the heredoc marker (`2>&1 |
# tee -a "$log"`), so that regex NEVER matched anything, block_start stayed
# 0 for every site, and the "block" was silently the ENTIRE FILE FROM LINE 0
# every time. That means site 1's mkdir (real, present) satisfied the check
# for sites 2 and 3 even with THEIR OWN mkdir deleted — verified live below
# before trusting the fix (see the self-test section). Fixed to bound each
# block by the nearest PRECEDING `VM_SCRIPT_INLINE <name>` call line (the
# real, unambiguous start of each remote script — six such calls exist in
# this file; the module's own line-number comment for a similar risk, run-
# arcs.sh's lineage-extraction fix earlier this same session, used the same
# "bound by call site, not by re-matching heredoc text" fix for an analogous
# bug) — and the test asserts, before running the real check, that this
# boundary actually discriminates blocks (three DISTINCT non-zero starts,
# one per copy site), so a future refactor that collapses the call sites
# back into ambiguity fails LOUD here rather than silently degrading back to
# whole-file scope.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
FILE="$ROOT/test/install-recovery/lib/lxd-backend.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

python3 - "$FILE" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
lines = text.split('\n')

copy_line_re = re.compile(r'cp /tmp/env-config\b')
block_open_re = re.compile(r'^\s*VM_SCRIPT_INLINE\b')
mkdir_maintenance_re = re.compile(r'install -d .*statbus-maintenance')

copy_sites = [i for i, l in enumerate(lines) if copy_line_re.search(l)]
if len(copy_sites) != 3:
    print(f"FAIL: expected exactly 3 env-config copy sites in {sys.argv[1]}, found {len(copy_sites)} — "
          f"update this test if a new install path was added or removed", file=sys.stderr)
    sys.exit(1)

block_starts = []
for site in copy_sites:
    # Walk backward to the nearest VM_SCRIPT_INLINE call line (the real
    # start of THIS remote script block) — never look further back than
    # that, so an earlier block's mkdir can't be mistaken for this one's.
    block_start = None
    for j in range(site, -1, -1):
        if block_open_re.search(lines[j]):
            block_start = j
            break
    if block_start is None:
        print(f"FAIL: env-config copy at line {site+1} has no preceding "
              f"VM_SCRIPT_INLINE call in the file at all — cannot bound its "
              f"remote-script block", file=sys.stderr)
        sys.exit(1)
    block_starts.append(block_start)

# Self-test (STATBUS-425 M3b R2): the whole point of bounding by
# VM_SCRIPT_INLINE call sites is that the three blocks are DISTINCT scopes.
# If block boundary resolution ever degenerates back to "always line 0" (the
# exact prior bug — the heredoc-marker regex never matched, so every site's
# search fell through to the top of the file), all three would collapse to
# the SAME start and this assertion catches it before the real check below
# ever gets a chance to (wrongly) pass.
if len(set(block_starts)) != 3:
    print(f"FAIL: block boundaries did not resolve to 3 distinct blocks "
          f"(got starts={block_starts}) — boundary detection has degenerated "
          f"to whole-file scope, the exact STATBUS-425 M3b R2 regression "
          f"this self-test exists to catch", file=sys.stderr)
    sys.exit(1)
print(f"PASS: 3 distinct remote-script block boundaries resolved: {block_starts}")

for site, block_start in zip(copy_sites, block_starts):
    block = lines[block_start:site]
    if not any(mkdir_maintenance_re.search(l) for l in block):
        print(f"FAIL: env-config copy at line {site+1} has no preceding "
              f"'install -d ... statbus-maintenance' in its own remote-script "
              f"block (block starts at line {block_start+1}) — this is the "
              f"exact STATBUS-425 M3a permission-denied regression shape", file=sys.stderr)
        sys.exit(1)
    print(f"PASS: env-config copy at line {site+1} is preceded by the statbus-maintenance mkdir in its own block (starting line {block_start+1})")

print("PASS: all 3 env-config pre-copy sites create ~/statbus-maintenance first, in their own distinct block")
PY

# Live-catches-the-regression self-test, run for real (not just described):
# delete the mkdir from the LAST site only (site 3), keeping site 1's intact
# — under the OLD (broken) boundary logic this would still PASS (site 1's
# mkdir satisfies the whole-file scan); under the fixed per-block boundary
# it must FAIL, naming site 3 specifically.
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
python3 - "$FILE" "$TMPFILE" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().split('\n')
copy_line_re = re.compile(r'cp /tmp/env-config\b')
mkdir_re = re.compile(r'install -d .*statbus-maintenance')
copy_sites = [i for i, l in enumerate(lines) if copy_line_re.search(l)]
last_site = copy_sites[-1]
# Remove the nearest preceding mkdir line to the LAST copy site only.
for j in range(last_site, -1, -1):
    if mkdir_re.search(lines[j]):
        del lines[j]
        break
open(dst, 'w').write('\n'.join(lines))
PY
if python3 - "$TMPFILE" <<'PY' >/dev/null 2>&1
import re, sys
text = open(sys.argv[1]).read()
lines = text.split('\n')
copy_line_re = re.compile(r'cp /tmp/env-config\b')
block_open_re = re.compile(r'^\s*VM_SCRIPT_INLINE\b')
mkdir_maintenance_re = re.compile(r'install -d .*statbus-maintenance')
copy_sites = [i for i, l in enumerate(lines) if copy_line_re.search(l)]
for site in copy_sites:
    block_start = 0
    for j in range(site, -1, -1):
        if block_open_re.search(lines[j]):
            block_start = j
            break
    block = lines[block_start:site]
    if not any(mkdir_maintenance_re.search(l) for l in block):
        sys.exit(1)
sys.exit(0)
PY
then
    fail "self-test did not catch a deleted mkdir at the last copy site — the fix does not actually discriminate per-block"
fi
echo "PASS: self-test confirms a mkdir removed from the last block's own scope is caught (was silently missed by the pre-R2 version of this test)"
