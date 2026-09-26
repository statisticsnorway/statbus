#!/bin/bash
# Interrupt the web entry point after Services, before the first migration.
# The database remains healthy. Recovery must complete seed, migration and readiness.
set -euo pipefail
VM_NAME="${1:-statbus-recovery-5-install-database-route-interrupted}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"
trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT
bootstrap_install_test_vm "$VM_NAME" ""
LOG="${HARNESS_ROOT}/tmp/install-recovery-${VM_NAME}-install.log"
MARKER="${HARNESS_ROOT}/tmp/install-recovery-${VM_NAME}-route-stopped"
FIRST_LOG="${HARNESS_ROOT}/tmp/install-recovery-${VM_NAME}-first.log"
SECOND_LOG="${HARNESS_ROOT}/tmp/install-recovery-${VM_NAME}-recovery.log"
rm -f "$MARKER" "$LOG" "$FIRST_LOG" "$SECOND_LOG"
# Watch the services completion boundary and kill only the route provider.
# The install can either use the in-service route or fail with a bounded diagnosis.
(
  for ((i=0; i<1200; i++)); do
    if grep -Eq '^\[[0-9]+/[0-9]+\] Services +(DONE|OK)' "$LOG" 2>/dev/null; then break; fi
    sleep 0.1
  done
  grep -Eq '^\[[0-9]+/[0-9]+\] Services +(DONE|OK)' "$LOG" || exit 1
  # A late stop is not an interrupted migration fixture.
  if grep -Eq '^\[[0-9]+/[0-9]+\] (Seed|Migrations) ' "$LOG"; then exit 1; fi
  VM_EXEC bash -c 'cd ~/statbus && docker compose --profile all stop proxy' || exit 1
  if grep -Eq '^\[[0-9]+/[0-9]+\] (Seed|Migrations) ' "$LOG"; then exit 1; fi
  date +%s > "$MARKER"
) &
watcher=$!
if install_statbus_in_vm "$VM_NAME"; then
  first_rc=0
else
  first_rc=$?
fi
kill "$watcher" 2>/dev/null || true
wait "$watcher" 2>/dev/null || true
test -f "$MARKER" || { echo 'route interruption did not occur' >&2; exit 1; }
stopped_at=$(cat "$MARKER")
if (( $(date +%s) - stopped_at > 300 )); then
  echo 'interrupted install did not fail within five minutes of route stop' >&2
  exit 1
fi
cp "$LOG" "$FIRST_LOG"
test "$first_rc" -ne 0 || { echo 'interrupted install unexpectedly succeeded' >&2; exit 1; }
grep -F 'web entry point' "$FIRST_LOG" >/dev/null || { echo 'missing route provider diagnosis' >&2; exit 1; }
grep -E '(127\.0\.0\.1|localhost):[0-9]+' "$FIRST_LOG" >/dev/null || { echo 'missing route address' >&2; exit 1; }
grep -Ei '(retry|rerun)' "$FIRST_LOG" >/dev/null || { echo 'missing recovery action' >&2; exit 1; }
# The harness appends to LOG; isolate each invocation before checking progress.
rm -f "$LOG"
# The installer repairs the stopped route on rerun.
install_statbus_in_vm "$VM_NAME"
cp "$LOG" "$SECOND_LOG"
grep -E '^\[[0-9]+/[0-9]+\] Seed +(DONE|OK)' "$SECOND_LOG" >/dev/null
grep -E '^\[[0-9]+/[0-9]+\] Migrations +(DONE|OK)' "$SECOND_LOG" >/dev/null
assert_step_upgrade_service_completed "$VM_NAME"
assert_health_passes "$VM_NAME"
VM_EXEC bash -c 'cd ~/statbus && echo "SELECT 1" | ./sb psql' | grep -q 1
echo 'PASS: database route interrupted and recovered through seed, migrations, and readiness'
