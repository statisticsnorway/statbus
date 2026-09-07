#!/bin/bash
# Arc: rollback-schema-floor-adoption (STATBUS-354 Phase 7 Arc A)
# A is the released pre-column baseline. B carries the rollback finishing column
# plus a final deterministic V_fail, so B applies the floor and then enters its
# built-in rollback. The rollback must restore A's snapshot, replay B's daemon
# floor with B's recovery binary, and publish A's binary only after cleanup.
set -euo pipefail
VM_NAME="${1:-statbus-arc-rollback-floor-adoption}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-1200}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
FLOOR=20260907120000
: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"
trap 'RC=$?; cleanup_vm "$VM_NAME"; exit $RC' EXIT
row_field() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT $1 FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n'; }
ledger_field() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT $1 FROM db.migration WHERE version = $FLOOR;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n'; }
backup_listing() { VM_EXEC bash -c "if [ -d ~/statbus-backups ]; then find ~/statbus-backups -mindepth 1 -maxdepth 1 -printf '%f\\n' | LC_ALL=C sort; fi"; }
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
BASELINE_FP=$(capture_db_fingerprint baseline)
BACKUPS_BEFORE=$(backup_listing)
BASE_SB=$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version 2>/dev/null | head -1')
arc_to "$B_FULL" "$B_BRANCH" "B (column adoption then deterministic failure)" "rolled_back"
[ "$(row_field state)" = rolled_back ] || { echo '✗ B is not rolled_back' >&2; exit 1; }
[ "$(row_field 'rollback_finish_pending_at IS NULL')" = t ] || { echo '✗ pending discriminator not cleared' >&2; exit 1; }
[ "$(ledger_field 'count(*)')" = 1 ] || { echo '✗ floor migration not recorded exactly once' >&2; exit 1; }
EXPECTED_HASH=$(VM_EXEC bash -c "cd ~/statbus && sha256sum migrations/${FLOOR}_*.up.sql | awk '{print \$1}'")
[ "$(ledger_field content_hash)" = "$EXPECTED_HASH" ] || { echo '✗ floor ledger hash differs from migration bytes' >&2; exit 1; }
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_fingerprint_matches "post-rollback == post-A data" "$BASELINE_FP" baseline
[ "$(VM_EXEC bash -c 'cd ~/statbus && git rev-parse HEAD')" = "$BASE_SHA" ] || { echo '✗ source A worktree not restored' >&2; exit 1; }
[ "$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version 2>/dev/null | head -1')" = "$BASE_SB" ] || { echo '✗ source A binary not canonical' >&2; exit 1; }
BACKUPS_AFTER=$(backup_listing)
[ "$BACKUPS_AFTER" = "$BACKUPS_BEFORE" ] || { printf '✗ backup root listing changed\n%s\n---\n%s\n' "$BACKUPS_BEFORE" "$BACKUPS_AFTER" >&2; exit 1; }
LOG_REL=$(row_field "COALESCE(log_relative_file_path,'')")
LOG=$(VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$LOG_REL'")
for needle in 'rollback' 'Restoring database' 'database container' "migrate up --to $FLOOR" 'Restoring git' 'sb.old' 'Starting services' 'rollback finishing' 'rolled_back' 'Publishing'; do
  printf '%s' "$LOG" | grep -qi "$needle" || { echo "✗ progress log missing: $needle" >&2; exit 1; }
done
printf '%s' "$LOG" | awk -v a='Restoring database' -v b='migrate up --to' -v c='Restoring git' 'index($0,a){x=NR} index($0,b){y=NR} index($0,c){z=NR} END{exit !(x&&y&&z&&x<y&&y<z)}' || { echo '✗ restore/floor/source log order wrong' >&2; exit 1; }
NR0=$(arc_nrestarts); sleep 5; NR1=$(arc_nrestarts); [ "$NR0" = "$NR1" ] || { echo '✗ automatic restart loop after rollback' >&2; exit 1; }
echo 'PASS: rollback schema floor adoption replayed and returned byte-identically to A'
