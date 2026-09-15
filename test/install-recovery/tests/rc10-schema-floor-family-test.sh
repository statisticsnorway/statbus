#!/bin/bash
# Bounded offline regression for the rc.10 schema-floor family harness predicates.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
WORKFLOW="$ROOT/.github/workflows/upgrade-arc-harness.yaml"
RESTORE_ARC="$ROOT/test/install-recovery/arcs/restore-broke-reattempt-arc.sh"
ADOPTION_ARC="$ROOT/test/install-recovery/arcs/rollback-schema-floor-adoption-arc.sh"
FAILURE_ARC="$ROOT/test/install-recovery/arcs/rollback-schema-floor-failure-arc.sh"
PRE_COLUMN=56559fa7a6683b0d7e2f8727091ed5bb7eb678cf
FLOOR_MIGRATION=migrations/20260907120000_statbus_347_rollback_finish_pending_column.up.sql

die() { echo "FAIL: $*" >&2; exit 1; }
assert_lineage() {
  local file=$1 scenario=$2 expected=$3
  python3 - "$file" "$scenario" "$expected" <<'PY'
import re, sys
text=open(sys.argv[1]).read(); scenario=sys.argv[2]; expected=sys.argv[3]
block=re.search(r'case "\$SCENARIO" in\n(?P<body>.*?)\n\s*esac', text, re.S)
if not block: raise SystemExit(2)
actual='working'
for patterns, value in re.findall(r'^\s*([^\n)]+)\)\s+lineage=([^ ;]+)', block.group('body'), re.M):
    if scenario in patterns.split('|'):
        actual=value; break
raise SystemExit(0 if actual == expected else 1)
PY
}
assert_restore_step() {
  local file=$1 value=$2
  python3 - "$file" "$value" <<'PY'
import re, sys
text=open(sys.argv[1]).read(); value=sys.argv[2]
m=re.search(r'\[ "\$STEP_AFTER_D5" = "([^"]+)" \]', text)
if not m: raise SystemExit(2)
raise SystemExit(0 if value == m.group(1) else 1)
PY
}

for scenario in rollback-schema-floor-adoption rollback-schema-floor-failure; do
  assert_lineage "$WORKFLOW" "$scenario" failing || die "$scenario is not routed to failing"
  ! assert_lineage "$WORKFLOW" "$scenario" working || die "$scenario incorrectly accepts working lineage"
done

# Old-code negative proof: removing the two cases reproduces the rc.10 fallthrough.
old=$(mktemp); trap 'rm -f "$old"' EXIT
sed 's/|rollback-schema-floor-adoption|rollback-schema-floor-failure//' "$WORKFLOW" > "$old"
for scenario in rollback-schema-floor-adoption rollback-schema-floor-failure; do
  ! assert_lineage "$old" "$scenario" failing || die "old resolver unexpectedly routes $scenario to failing"
  assert_lineage "$old" "$scenario" working || die "old resolver did not reproduce working fallthrough"
done

grep -q "SCHEMA_FLOOR_BASE_SHA=$PRE_COLUMN" "$WORKFLOW" || die 'pre-column floor baseline is not exported'
for arc in "$ADOPTION_ARC" "$FAILURE_ARC"; do
  grep -q 'BASE_SHA="${SCHEMA_FLOOR_BASE_SHA:-${BASE_SHA:-}}"' "$arc" || die "$(basename "$arc") does not consume floor baseline"
done
git -C "$ROOT" cat-file -e "$PRE_COLUMN^{commit}"
[ "$(git -C "$ROOT" rev-parse 012ca22da^)" = "$PRE_COLUMN" ] || die 'floor baseline is not the parent of the first column migration'
! git -C "$ROOT" cat-file -e "$PRE_COLUMN:$FLOOR_MIGRATION" 2>/dev/null || die 'floor baseline already contains the floor migration'
git -C "$ROOT" cat-file -e "HEAD:$FLOOR_MIGRATION" || die 'candidate tree lacks the floor migration required in failing B'
grep -q 'construct_upgrade_target "$base_sha" failing' "$WORKFLOW" || die 'failing B is not constructed from the candidate base'

assert_restore_step "$RESTORE_ARC" rollback || die 'C9 predicate does not accept StepRollback'
! assert_restore_step "$RESTORE_ARC" migrate-up || die 'C9 predicate still accepts stale migrate-up'
! assert_restore_step "$RESTORE_ARC" boot-migrate || die 'C9 predicate fails open on a wrong step'
# Old-code negative proof for the assertion itself.
old_arc=$(mktemp); trap 'rm -f "$old" "$old_arc"' EXIT
sed 's/\[ "$STEP_AFTER_D5" = "rollback" \]/[ "$STEP_AFTER_D5" = "migrate-up" ]/' "$RESTORE_ARC" > "$old_arc"
! assert_restore_step "$old_arc" rollback || die 'old assertion unexpectedly accepts observed StepRollback'
assert_restore_step "$old_arc" migrate-up || die 'old assertion negative control was not constructed'

echo 'PASS: rc.10 schema-floor family predicates are candidate-failing/pre-column and C9 requires StepRollback'
