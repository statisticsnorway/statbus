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
# The workflow exports this only for the schema-floor family. Keep BASE_SHA as
# the public arc input, but replace the ordinary candidate base with the exact
# pre-column snapshot baseline. B still comes from the candidate-based failing
# lineage and therefore carries current STATBUS-354 code, the floor migration,
# and the final V_fail that enters rollback.
BASE_SHA="${SCHEMA_FLOOR_BASE_SHA:-${BASE_SHA:-}}"
: "${BASE_SHA:?BASE_SHA or SCHEMA_FLOOR_BASE_SHA required}"
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
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
BASELINE_FP=$(capture_db_fingerprint baseline)
BASE_SB=$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version 2>/dev/null | head -1')
arc_to "$B_FULL" "$B_BRANCH" "B (column adoption then deterministic failure)" "rolled_back"
[ "$(row_field state)" = rolled_back ] || { echo '✗ B is not rolled_back' >&2; exit 1; }
[ "$(row_field 'rollback_finish_pending_at IS NULL')" = t ] || { echo '✗ pending discriminator not cleared' >&2; exit 1; }
[ "$(ledger_field 'count(*)')" = 1 ] || { echo '✗ floor migration not recorded exactly once' >&2; exit 1; }
# The floor migration file lives in B's tree. After the rollback the worktree is
# restored to A (pre-column), where that file does not exist, so hash the bytes
# from B's commit object instead of the current checkout. The runner has the full
# fixture history (fetch-depth: 0), so git show resolves B_FULL without the VM.
FLOOR_MIGRATION_FILE=$(git ls-tree --name-only "$B_FULL" -- migrations/ | grep "^migrations/${FLOOR}_" | grep '\.up\.sql$' | head -1)
[ -n "$FLOOR_MIGRATION_FILE" ] || { echo "✗ could not resolve B's floor migration file" >&2; exit 1; }
EXPECTED_HASH=$(git show "$B_FULL:$FLOOR_MIGRATION_FILE" | sha256sum | awk '{print $1}')
[ "$(ledger_field content_hash)" = "$EXPECTED_HASH" ] || { echo '✗ floor ledger hash differs from migration bytes' >&2; exit 1; }
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
# The full 3-dim fingerprint is the wrong tool here: this scenario intentionally
# re-applies the daemon floor during rollback, so SCHEMA and LEDGER legitimately
# advance past A (failure_code enum, rollback_finish_pending_at, the floor ledger
# row). The clean-slate guarantee that matters is the DATA dim — compare that only.
BASELINE_DATA=$(echo "$BASELINE_FP" | awk '{print $3}')
RECHECK_DATA=$(capture_db_fingerprint rollback-recheck | awk '{print $3}')
[ "$RECHECK_DATA" = "$BASELINE_DATA" ] || { echo "✗ DATA clean-slate mismatch (post-rollback != post-A base data)" >&2; exit 1; }
[ "$(VM_EXEC bash -c 'cd ~/statbus && git rev-parse HEAD')" = "$BASE_SHA" ] || { echo '✗ source A worktree not restored' >&2; exit 1; }
[ "$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version 2>/dev/null | head -1')" = "$BASE_SB" ] || { echo '✗ source A binary not canonical' >&2; exit 1; }
VM_EXEC bash -c 'test -d ~/statbus-backups/pre-upgrade-active' || { echo '✗ committed persistent backup absent after rollback' >&2; exit 1; }
! VM_EXEC bash -c 'test -e ~/statbus-backups/pre-upgrade-syncing' || { echo '✗ incomplete syncing backup remains after rollback' >&2; exit 1; }
assert_no_orphan_backup "$VM_NAME"
VM_EXEC bash -c "find ~/statbus-backups -mindepth 2 -maxdepth 2 -type f -path '*/upgrade-logs-*/*.log' -print -quit | grep -q ." || { echo '✗ expected forensic upgrade logs absent beside backup' >&2; exit 1; }
LOG_REL=$(row_field "COALESCE(log_relative_file_path,'')")
LOG=$(VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$LOG_REL'")
for needle in 'rollback' 'Restoring database' 'Starting only the restored database for schema-floor replay ... healthy' "migrate up --to $FLOOR" 'Restoring git' 'sb.old' 'Starting services' 'rollback finishing' 'rolled_back' 'Publishing'; do
  printf '%s' "$LOG" | grep -qi "$needle" || { echo "✗ progress log missing: $needle" >&2; exit 1; }
done
printf '%s' "$LOG" | awk -v a='Restoring database' -v b='migrate up --to' -v c='Restoring git' 'index($0,a){x=NR} index($0,b){y=NR} index($0,c){z=NR} END{exit !(x&&y&&z&&x<y&&y<z)}' || { echo '✗ restore/floor/source log order wrong' >&2; exit 1; }
NR0=$(arc_nrestarts); sleep 5; NR1=$(arc_nrestarts); [ "$NR0" = "$NR1" ] || { echo '✗ automatic restart loop after rollback' >&2; exit 1; }
echo 'PASS: rollback schema floor adoption replayed and returned byte-identically to A'
