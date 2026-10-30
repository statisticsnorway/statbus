#!/bin/bash
# STATBUS-551: a worker that starts inside the upgrade's read-only window still
# restores missing recurring maintenance tasks once the database is writable.
#
# The upgrade sets ALTER DATABASE ... SET default_transaction_read_only = on
# and starts the new worker before lifting it (rc.02 LXD run 41108121046: worker
# up 18:43:52, writes unblocked 18:43:56). A recurring command exists only while
# it has a pending row, so a box that lost one depends on this startup repair.
#
# The test runs the real worker binary against an isolated copy of the test
# template: task_cleanup's pending row is removed, the database is made
# read-only, the worker starts, and the database is made writable 6 s later.
# The worker must then have recreated task_cleanup's pending row.
#
# Usage: test/worker-seed-read-only-test.sh   (local dev stack must be up)
#   WORKER_IN_CONTAINER=1 runs the worker binary inside the compose worker
#   container (the published image for this commit), as Fast Tests does.
set -euo pipefail

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE"
BINARY="$WORKSPACE/cli/bin/statbus"
TEMPLATE_DB="${POSTGRES_TEST_DB:-statbus_test_template}"
TEST_DB="test_worker_seed_ro_$$"
LOG="$WORKSPACE/tmp/test-worker-seed-read-only-$$.log"
mkdir -p "$WORKSPACE/tmp"

[ "${WORKER_IN_CONTAINER:-0}" = "1" ] || [ -x "$BINARY" ] || { echo "FAIL: worker binary missing: build with (cd cli && shards build statbus)"; exit 1; }

psql_db() { ./sb psql -d "$1" -v ON_ERROR_STOP=1 -At; }

WORKER_PID=""
cleanup() {
    if [ -n "$WORKER_PID" ] && kill -0 "$WORKER_PID" 2>/dev/null; then
        kill -TERM "$WORKER_PID" 2>/dev/null || true
        for _ in $(seq 1 20); do kill -0 "$WORKER_PID" 2>/dev/null || break; sleep 0.5; done
        kill -KILL "$WORKER_PID" 2>/dev/null || true
    fi
    echo "DROP DATABASE IF EXISTS \"$TEST_DB\" WITH (FORCE);" | psql_db postgres >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "CREATE DATABASE \"$TEST_DB\" WITH TEMPLATE $TEMPLATE_DB;" | psql_db postgres >/dev/null
echo "DELETE FROM worker.tasks WHERE command = 'task_cleanup' AND state = 'pending';" | psql_db "$TEST_DB" >/dev/null
echo "ALTER DATABASE \"$TEST_DB\" SET default_transaction_read_only = on;" | psql_db postgres >/dev/null

if [ "${WORKER_IN_CONTAINER:-0}" = "1" ]; then
    # timeout bounds the in-container process: signals to the exec client do
    # not reach it, and the DROP ... WITH (FORCE) in cleanup closes its sessions.
    docker compose exec -T worker timeout 90 /app/bin/statbus worker --database "$TEST_DB" > "$LOG" 2>&1 &
else
    "$BINARY" worker --database "$TEST_DB" > "$LOG" 2>&1 &
fi
WORKER_PID=$!

sleep 6
echo "ALTER DATABASE \"$TEST_DB\" SET default_transaction_read_only = off;" | psql_db postgres >/dev/null

restored=""
for _ in $(seq 1 60); do
    restored=$(echo "SELECT count(*) FROM worker.tasks WHERE command = 'task_cleanup' AND state = 'pending';" | psql_db "$TEST_DB")
    [ "$restored" = "1" ] && break
    sleep 0.5
done

echo "--- worker log (seed lines) ---"
grep -E "recurring maintenance|read-only" "$LOG" || true
echo "---"

if [ "$restored" != "1" ]; then
    echo "FAIL: task_cleanup has no pending row 30 s after the database became writable (log: $LOG)"
    exit 1
fi
grep -q "Seeded missing recurring maintenance task(s): task_cleanup" "$LOG" \
    || { echo "FAIL: the worker did not report restoring task_cleanup (log: $LOG)"; exit 1; }
echo "PASS: a worker started read-only restored task_cleanup once the database became writable"
