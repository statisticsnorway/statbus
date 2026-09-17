#!/bin/bash

schema_floor_progress_line() {
  printf 'Re-applying rollback daemon schema floor through db.migration: %s' "$1"
}

assert_schema_floor_adoption_progress() {
  local log=$1 floor=$2 needle
  local floor_line
  floor_line=$(schema_floor_progress_line "$floor")
  for needle in \
    'rollback' \
    'Restoring database' \
    'Starting only the restored database for schema-floor replay ... healthy' \
    "$floor_line" \
    'Restoring git' \
    'sb.old' \
    'Starting services' \
    'rollback finishing' \
    'rolled_back' \
    'Publishing'; do
    grep -qiF "$needle" <<<"$log" || {
      echo "✗ progress log missing: $needle" >&2
      return 1
    }
  done
  printf '%s' "$log" | awk -v a='Restoring database' -v b="$floor_line" -v c='Restoring git' \
    'index($0,a){x=NR} index($0,b){y=NR} index($0,c){z=NR} END{exit !(x&&y&&z&&x<y&&y<z)}' || {
    echo '✗ restore/floor/source log order wrong' >&2
    return 1
  }
}

assert_schema_floor_retry_order() {
  local log=$1 floor=$2
  local floor_line
  floor_line=$(schema_floor_progress_line "$floor")
  printf '%s' "$log" | awk -v a='Restoring database' -v b="$floor_line" -v c='Publishing' \
    'index($0,a){x=NR} index($0,b){y=NR} index($0,c){z=NR} END{exit !(x&&y&&z&&x<y&&y<z)}' || {
    echo '✗ retry log order is not restore < floor replay < publish' >&2
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
