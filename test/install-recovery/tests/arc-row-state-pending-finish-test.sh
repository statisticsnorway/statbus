#!/bin/bash
# An arc's upgrade-state reader reports a rollback whose final row transition
# is still pending as 'finishing_rollback', so a poll landing in that window
# keeps waiting. A terminal failure still reads 'failed', and a finished
# rollback 'rolled_back'.
#
# The v2026.10.5-rc.03 arc postswap-rollback-restore-watchdog (run
# 40977271679) read state='failed' (rollback_finish_pending_at set) and failed
# while the row reached rolled_back in the same second. This test runs the
# REAL row_state definition from that arc against the local development
# database (VM_EXEC is a local shim). It works in a throwaway database cloned
# from the migrated seed (POSTGRES_SEED_DB), so neither the app nor the seed
# database is written, and drops it on exit.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ARC="$ROOT/test/install-recovery/arcs/postswap-rollback-restore-watchdog-arc.sh"
cd "$ROOT"
if ! echo 'SELECT 1;' | ./sb psql -t -A >/dev/null 2>&1; then
    # Fast Tests sets ARC_ROW_STATE_REQUIRE_DB=1, where a skip would be a pass
    # that tested nothing.
    [ "${ARC_ROW_STATE_REQUIRE_DB:-0}" = 1 ] && { echo "FAIL: no database reachable via ./sb psql" >&2; exit 1; }
    echo "SKIP: no local database (./sb psql)"; exit 0
fi
SEED_DB=$(./sb dotenv -f .env get POSTGRES_SEED_DB)
SCRATCH_DB="arc_row_state_$$"
echo "CREATE DATABASE $SCRATCH_DB TEMPLATE $SEED_DB;" | PGDATABASE=postgres ./sb psql -q -v ON_ERROR_STOP=1 >/dev/null
cleanup() { echo "DROP DATABASE IF EXISTS $SCRATCH_DB;" | PGDATABASE=postgres ./sb psql -q >/dev/null 2>&1 || true; }
trap cleanup EXIT
export PGDATABASE=$SCRATCH_DB
[ "$(echo "SELECT to_regclass('public.upgrade') IS NOT NULL;" | ./sb psql -t -A)" = t ] || {
    echo "FAIL: $SEED_DB has no public.upgrade; the seed is not migrated" >&2; exit 1; }
# shellcheck source=../lib/assertions.sh
source "$ROOT/test/install-recovery/lib/assertions.sh"

FIXTURE_SHA=$(printf 'f%.0s' $(seq 1 40))
# Local shim with VM_EXEC's contract: run the command as a shell in the
# checkout, where ~/statbus is this repository.
VM_EXEC() { HOME_OVERRIDE="$ROOT" bash -c "${3//\~\/statbus/$ROOT}"; }
B_FULL=$FIXTURE_SHA
eval "$(grep -E '^row_state\(\)' "$ARC")"

with_row() {
    local state=$1 pending=$2
    local extra_cols="" extra_vals=""
    case "$state" in
        failed) extra_cols=", error"; extra_vals=", 'fixture failure'" ;;
        rolled_back) extra_cols=", error, rolled_back_at"; extra_vals=", 'fixture failure', now()" ;;
    esac
    [ "$pending" = yes ] && { extra_cols="$extra_cols, rollback_finish_pending_at"; extra_vals="$extra_vals, now()"; }
    ./sb psql -q -t -A >/dev/null <<SQL
DELETE FROM public.upgrade WHERE commit_sha = '$FIXTURE_SHA';
INSERT INTO public.upgrade (commit_sha, committed_at, summary, state, scheduled_at, started_at$extra_cols)
VALUES ('$FIXTURE_SHA', now(), 'arc row-state fixture', '$state', now(), now()$extra_vals);
SQL
}

# The arc's own terminal decision after release.
arc_verdict() {
    case "$1" in
        rolled_back) echo terminal-ok ;;
        completed|failed) echo terminal-fail ;;
        *) echo keep-waiting ;;
    esac
}

check() {
    local label=$1 state=$2 pending=$3 want_state=$4 want_verdict=$5 got
    with_row "$state" "$pending"
    got=$(row_state)
    [ "$got" = "$want_state" ] || { echo "FAIL: $label: row_state='$got', want '$want_state'" >&2; exit 1; }
    [ "$(arc_verdict "$got")" = "$want_verdict" ] || { echo "FAIL: $label: arc verdict '$(arc_verdict "$got")', want '$want_verdict'" >&2; exit 1; }
    echo "PASS: $label -> row_state=$got, arc $want_verdict"
}

check "rollback with final transition pending" failed yes finishing_rollback keep-waiting
check "terminal failure" failed no failed terminal-fail
check "finished rollback" rolled_back no rolled_back terminal-ok
echo "arc row-state tests: PASS"
