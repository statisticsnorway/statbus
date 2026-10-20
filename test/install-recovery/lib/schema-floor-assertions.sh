#!/bin/bash

resolve_candidate_daemon_floor() {
  local candidate_commit=$1 daemon_floor floor_migration
  daemon_floor=$(git show "$candidate_commit:cli/internal/migrate/daemon_floor.go" | awk '
    $1 == "const" && $2 == "DaemonSchemaFloor" && $3 == "int64" && $4 == "=" { print $5 }
  ')
  [[ "$daemon_floor" =~ ^[0-9]{14}$ ]] || {
    echo "✗ could not resolve candidate DaemonSchemaFloor" >&2
    return 1
  }
  floor_migration=$(git ls-tree --name-only "$candidate_commit" -- migrations/ | grep "^migrations/${daemon_floor}_.*\.up\.sql$" || true)
  [ "$(printf '%s\n' "$floor_migration" | grep -c .)" = 1 ] || {
    echo "✗ candidate DaemonSchemaFloor does not identify exactly one up migration" >&2
    return 1
  }
  printf '%s\n' "$daemon_floor"
}

schema_floor_progress_line() {
  printf 'Re-applying rollback daemon schema floor through db.migration: %s' "$1"
}

assert_schema_floor_retry_order() {
  local log=$1 floor=$2
  local floor_line source_binary_line
  floor_line=$(schema_floor_progress_line "$floor")
  source_binary_line='Restoring ./sb from ./sb.old ... ok'
  printf '%s' "$log" | awk -v a='Restoring database' -v b="$floor_line" -v c='Starting services' -v d="$source_binary_line" \
    'index($0,a){w=NR} index($0,b){x=NR} index($0,c){y=NR} index($0,d){z=NR} END{exit !(w&&x&&y&&z&&w<x&&x<y&&y<z)}' || {
    echo '✗ retry log order is not database restore < floor replay < service start < source binary restore' >&2
    return 1
  }
}

# Run a command under `set -e` while accepting rollback()'s documented
# EX_TEMPFAIL control exit. The observed code is exported through the global so
# callers and offline tests can prove that 75 was handled rather than erased.
ROLLBACK_CONTROL_EXIT_RC=0
run_accepting_rollback_control_exit() {
  local rc=0
  "$@" || rc=$?
  ROLLBACK_CONTROL_EXIT_RC=$rc
  case "$rc" in
    0|75) return 0 ;;
    *) return "$rc" ;;
  esac
}
