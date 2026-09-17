#!/bin/bash
# Bounded offline regression for the rc.10 schema-floor family harness predicates.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
WORKFLOW="$ROOT/.github/workflows/upgrade-arc-harness.yaml"
RESTORE_ARC="$ROOT/test/install-recovery/arcs/restore-broke-reattempt-arc.sh"
ADOPTION_ARC="$ROOT/test/install-recovery/arcs/rollback-schema-floor-adoption-arc.sh"
FAILURE_ARC="$ROOT/test/install-recovery/arcs/rollback-schema-floor-failure-arc.sh"
SCHEMA_FLOOR_ASSERTIONS="$ROOT/test/install-recovery/lib/schema-floor-assertions.sh"
PRE_COLUMN=d53731ec539b03b9378ff8828bb2be938d9e2e0f
FLOOR_MIGRATION=migrations/20260907120000_statbus_347_rollback_finish_pending_column.up.sql
source "$SCHEMA_FLOOR_ASSERTIONS"

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
assert_floor_failure_retry_guard() {
  local file=$1
  python3 - "$file" <<'PY'
import re, sys
text=open(sys.argv[1]).read()
pattern=r'run_accepting_rollback_control_exit\s+VM_EXEC\s+bash\s+-c\s+"[^"\n]*\./sb install"\s*\|\|\s*\{'
raise SystemExit(0 if re.search(pattern, text) else 1)
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
[ "$(git -C "$ROOT" rev-parse 'v2026.09.0^{commit}')" = "$PRE_COLUMN" ] || die 'floor baseline is not the released v2026.09.0 (a pre-column release with a retained image)'
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

# The helper test below is insufficient by itself: the real failure was that the
# arc invoked VM_EXEC directly under set -e and never used the helper. Pin the
# wiring at the human retry site, with the rejected unguarded form as a mutation.
assert_floor_failure_retry_guard "$FAILURE_ARC" || die 'floor-failure human retry is not wrapped by run_accepting_rollback_control_exit'
unguarded_arc=$(mktemp)
trap 'rm -f "$old" "$old_arc" "$unguarded_arc"' EXIT
sed 's/run_accepting_rollback_control_exit VM_EXEC/VM_EXEC/' "$FAILURE_ARC" > "$unguarded_arc"
! assert_floor_failure_retry_guard "$unguarded_arc" || die 'unguarded floor-failure retry mutation was not caught'

# Execute the exact helpers used by both arcs. This is deliberately stronger
# than bash -n or grep-only source inspection: it catches set -e control-flow
# mistakes and validates the stable product progress contract end to end.
FLOOR_LINE=$(schema_floor_progress_line 20260907120000)
ADOPTION_LOG=$(cat <<EOF
rollback
Restoring database
Starting only the restored database for schema-floor replay ... healthy
$FLOOR_LINE
Restoring git
sb.old
Starting services
rollback finishing
rolled_back
Publishing
EOF
)
assert_schema_floor_adoption_progress "$ADOPTION_LOG" 20260907120000 || die 'stable schema-floor progress line was rejected'
OLD_ARGV_LOG=${ADOPTION_LOG/$FLOOR_LINE/migrate up --to 20260907120000}
! assert_schema_floor_adoption_progress "$OLD_ARGV_LOG" 20260907120000 >/dev/null 2>&1 || die 'stale unlogged migrate argv still satisfies the adoption assertion'
WRONG_ORDER_LOG=$(printf '%s\n' 'rollback' "$FLOOR_LINE" 'Restoring database' 'Starting only the restored database for schema-floor replay ... healthy' 'Restoring git' 'sb.old' 'Starting services' 'rollback finishing' 'rolled_back' 'Publishing')
! assert_schema_floor_adoption_progress "$WRONG_ORDER_LOG" 20260907120000 >/dev/null 2>&1 || die 'adoption log order fails open'

continued=no
run_accepting_rollback_control_exit bash -c 'exit 75'
continued=yes
[ "$continued" = yes ] || die 'documented rollback exit 75 aborted execution under set -e'
[ "$ROLLBACK_CONTROL_EXIT_RC" = 75 ] || die 'rollback exit helper did not preserve observed exit 75'
run_accepting_rollback_control_exit bash -c 'exit 0' || die 'success exit 0 was rejected'
! run_accepting_rollback_control_exit bash -c 'exit 74' || die 'unexpected exit 74 was accepted'
assert_schema_floor_retry_order "Restoring database
$FLOOR_LINE
Publishing" 20260907120000 || die 'retry stable progress order was rejected'
! assert_schema_floor_retry_order "$FLOOR_LINE
Restoring database
Publishing" 20260907120000 >/dev/null 2>&1 || die 'retry order fails open'

echo 'PASS: rc.10 schema-floor family predicates and executable progress/exit-control paths are correct'
