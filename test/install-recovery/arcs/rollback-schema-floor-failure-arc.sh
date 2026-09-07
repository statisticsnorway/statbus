#!/bin/bash
# Arc: rollback-schema-floor-failure (STATBUS-354 Phase 7 Arc B)
# The injected error exists only in rollback-time floor reapplication. Forward
# migration remains genuine. A final V_fail enters built-in rollback.
set -euo pipefail
VM_NAME="${1:-statbus-arc-rollback-floor-failure}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
FLOOR=20260907120000
INJECT_CLASS=rollback-floor-reapply
UPGRADE_UNIT=statbus-upgrade@statbus.service
: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"
trap 'RC=$?; cleanup_vm "$VM_NAME"; exit $RC' EXIT
row_field() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT $1 FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n'; }
flag_field() { VM_EXEC bash -c "python3 -c \"import json; print(json.load(open('/home/statbus/statbus/tmp/upgrade-in-progress.json'))['$1'])\"" 2>/dev/null | tr -d '\r\n'; }
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
BASELINE_FP=$(capture_db_fingerprint baseline)
BASE_SB=$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version 2>/dev/null | head -1')
VM_EXEC bash -c "cd ~/statbus && git fetch origin '$B_BRANCH' && git cat-file -e '$B_FULL' && ./sb upgrade register '$B_FULL'"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
arc_schedule_daemon_down "$B_FULL"
arc_install_dispatch_with_inject "$INJECT_CLASS" || true
[ "$(row_field state)" = in_progress ] || { echo '✗ floor failure did not retain in_progress' >&2; exit 1; }
[ "$(row_field failure_code)" = ROLLBACK_SCHEMA_FLOOR_FAILED ] || { echo '✗ durable failure code absent' >&2; exit 1; }
[ "$(flag_field step)" = rollback ] || { echo '✗ marker is not StepRollback' >&2; exit 1; }
[ "$(flag_field phase)" = rollback_schema_floor_failed ] || { echo '✗ marker is not floor-failure phase' >&2; exit 1; }
[ "$(VM_EXEC bash -c 'cd ~/statbus && git rev-parse HEAD')" = "$B_FULL" ] || { echo '✗ target tree not retained' >&2; exit 1; }
[ "$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version 2>/dev/null | head -1')" != "$BASE_SB" ] || { echo '✗ target sb not retained' >&2; exit 1; }
for svc in app worker rest; do VM_EXEC bash -c "cd ~/statbus && ! docker compose ps --status running --services | grep -qx '$svc'" || { echo "✗ $svc is running" >&2; exit 1; }; done
VM_EXEC bash -c 'test -e ~/statbus-maintenance/active' || { echo '✗ HTTP maintenance absent' >&2; exit 1; }
[ "$(VM_EXEC bash -c "cd ~/statbus && echo 'SHOW default_transaction_read_only;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')" = on ] || { echo '✗ SQL read-only absent' >&2; exit 1; }
VM_EXEC bash -c "cd ~/statbus && echo 'SELECT 1' | ./sb psql -t -A" >/dev/null || { echo '✗ DB unavailable for diagnosis' >&2; exit 1; }
[ "$(row_field 'rollback_finish_pending_at IS NULL')" = t ] || { echo '✗ pending write occurred' >&2; exit 1; }
! VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD | grep -qx '$BASE_SHA'" || { echo '✗ source checkout occurred' >&2; exit 1; }
NR0=$(arc_nrestarts); sleep 8; NR1=$(arc_nrestarts); [ "$NR0" = "$NR1" ] || { echo '✗ daemon restart count did not freeze' >&2; exit 1; }
LOG_REL=$(row_field "COALESCE(log_relative_file_path,'')"); LOG=$(VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$LOG_REL'")
printf '%s' "$LOG" | grep -q ROLLBACK_SCHEMA_FLOOR_FAILED || { echo '✗ failure missing from progress log' >&2; exit 1; }
for forbidden in 'Rollback to the previous version complete' 'rolled_back' 'Publishing source binary'; do ! printf '%s' "$LOG" | grep -q "$forbidden" || { echo "✗ forbidden success log: $forbidden" >&2; exit 1; }; done
# Human-gated retry. Removing injection and running plain install must restore the
# snapshot again before ordinary floor migration, finish, and publish A last.
VM_EXEC bash -c "rm -f ~/.config/systemd/user/${UPGRADE_UNIT}.d/90-statbus-inject.conf; systemctl --user daemon-reload; cd ~/statbus && ./sb install"
[ "$(row_field state)" = rolled_back ] || { echo '✗ human retry did not roll back' >&2; exit 1; }
[ "$(row_field 'rollback_finish_pending_at IS NULL')" = t ] || { echo '✗ pending not cleared after retry' >&2; exit 1; }
[ "$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT count(*) FROM db.migration WHERE version=$FLOOR;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')" = 1 ] || { echo '✗ ordinary floor migration not recorded once' >&2; exit 1; }
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_fingerprint_matches "post-retry == post-A data" "$BASELINE_FP" baseline
[ "$(VM_EXEC bash -c 'cd ~/statbus && git rev-parse HEAD')" = "$BASE_SHA" ] || { echo '✗ source tree not restored after retry' >&2; exit 1; }
[ "$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version 2>/dev/null | head -1')" = "$BASE_SB" ] || { echo '✗ source binary not published last' >&2; exit 1; }
LOG=$(VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$LOG_REL'")
printf '%s' "$LOG" | awk '/Restoring database/{r=NR} /migrate up --to/{m=NR} /Publishing/{p=NR} END{exit !(r&&m&&p&&r<m&&m<p)}' || { echo '✗ retry log order is not restore < migrate < publish' >&2; exit 1; }
echo 'PASS: rollback floor failure held closed and plain install converged'
