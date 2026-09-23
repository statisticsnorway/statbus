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

legacy_source_era_progress_label() {
  printf 'legacy source era (pre-capture release)'
}

assert_schema_floor_adoption_progress() {
  local log=$1 floor=$2
  local floor_line legacy_source_era_label
  floor_line=$(schema_floor_progress_line "$floor")
  legacy_source_era_label=$(legacy_source_era_progress_label)

  # The adoption arc separately proves the durable terminal and health gate.
  # Progress is evidence only for the two documented semantics specific to this
  # pre-capture source: the daemon floor was replayed through db.migration, and
  # source convergence used the explicitly labeled legacy compatibility path.
  # Do not pin internal rollback step wording or ordering here.
  grep -qF "$floor_line" <<<"$log" || {
    echo "✗ progress log missing semantic schema-floor replay: $floor_line" >&2
    return 1
  }
  grep -qF "$legacy_source_era_label" <<<"$log" || {
    echo "✗ progress log missing documented source-era label: $legacy_source_era_label" >&2
    return 1
  }
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
