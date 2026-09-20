#!/bin/bash
# Offline regression test for the rollback handoff database-read retries.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/install-recovery/lib/assertions.sh"
source "$ROOT/test/install-recovery/lib/arc-helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-db-query-retry.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
export HARNESS_ROOT="$TMP_ROOT"
export HARNESS_DB_QUERY_RETRY_TIMEOUT_S=5
export HARNESS_DB_QUERY_RETRY_INTERVAL_S=0
VM_NAME=test-vm
VM_IP=127.0.0.1
SSH_OPTS=(-o MockOption=yes)

sleep() { :; }
wait_for_worker_quiesce() { return 0; }

# snapshot_demo_data_counts: the first SSH query fails, the second succeeds.
echo 0 > "$TMP_ROOT/ssh-attempts"
ssh() {
    local attempt
    attempt=$(( $(cat "$TMP_ROOT/ssh-attempts") + 1 ))
    echo "$attempt" > "$TMP_ROOT/ssh-attempts"
    if [ "$attempt" -eq 1 ]; then
        echo 'psql: source daemon is restarting' >&2
        return 1
    fi
    echo 'statistical_unit=4,legal_unit=3,establishment=2,statistical_history=1'
}

snapshot=$(snapshot_demo_data_counts "$VM_NAME" 2>"$TMP_ROOT/snapshot.stderr")
[ "$snapshot" = 'statistical_unit=4,legal_unit=3,establishment=2,statistical_history=1' ]
[ "$(cat "$TMP_ROOT/ssh-attempts")" = 2 ]
grep -q 'demo-data count query.*retrying' "$TMP_ROOT/snapshot.stderr"
echo 'PASS: demo-data snapshot retries a failed query and returns only the successful result'

# capture_db_fingerprint: model psql | sha256sum printing SHA256("") while
# returning nonzero under pipefail. The helper must discard it, retry, and emit
# only the successful ledger hash in its unchanged three-field interface.
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
LEDGER_SHA=1111111111111111111111111111111111111111111111111111111111111111
DATA_SHA=2222222222222222222222222222222222222222222222222222222222222222
echo 0 > "$TMP_ROOT/ledger-attempts"
VM_EXEC() {
    local command_string="$*"
    case "$command_string" in
        *'POSTGRES_APP_DB'*) echo statbus_test ;;
        *'POSTGRES_ADMIN_USER'*) echo postgres ;;
        *'pg_dump --schema-only'*) echo 'CREATE TABLE public.retry_fixture (id integer);' ;;
        *'FROM db.migration'*)
            local attempt
            attempt=$(( $(cat "$TMP_ROOT/ledger-attempts") + 1 ))
            echo "$attempt" > "$TMP_ROOT/ledger-attempts"
            if [ "$attempt" -eq 1 ]; then
                echo "$EMPTY_SHA"
                echo 'psql: source daemon is restarting' >&2
                return 1
            fi
            echo "$LEDGER_SHA"
            ;;
        *'FROM public.legal_unit'*) echo "$DATA_SHA" ;;
        *) echo "unexpected VM_EXEC call: $command_string" >&2; return 2 ;;
    esac
}

fingerprint=$(capture_db_fingerprint retry-test 2>"$TMP_ROOT/fingerprint.stderr")
read -r schema_sha ledger_sha data_sha <<< "$fingerprint"
[ -n "$schema_sha" ]
[ "$ledger_sha" = "$LEDGER_SHA" ]
[ "$ledger_sha" != "$EMPTY_SHA" ]
[ "$data_sha" = "$DATA_SHA" ]
[ "$(cat "$TMP_ROOT/ledger-attempts")" = 2 ]
grep -q 'ledger query.*retrying' "$TMP_ROOT/fingerprint.stderr"
echo 'PASS: fingerprint retries a failed ledger query and never accepts the empty-input hash'

# A permanently unreadable query must fail loudly instead of returning empty
# stdout that a caller could mistake for a valid snapshot.
ssh() {
    echo 'psql: still unavailable' >&2
    echo 'DETAIL: database system is starting up' >&2
    return 1
}
HARNESS_DB_QUERY_RETRY_TIMEOUT_S=0
failed_output='sentinel'
if failed_output=$(snapshot_demo_data_counts "$VM_NAME" 2>"$TMP_ROOT/permanent.stderr"); then
    echo 'FAIL: permanently failed query unexpectedly succeeded' >&2
    exit 1
fi
[ -z "$failed_output" ]
grep -q 'failed after 1 attempt' "$TMP_ROOT/permanent.stderr"
grep -q 'psql: still unavailable' "$TMP_ROOT/permanent.stderr"
grep -q 'DETAIL: database system is starting up' "$TMP_ROOT/permanent.stderr"
echo 'PASS: exhausted database reads fail loudly with no snapshot output'

# A zero-exit pipeline that nevertheless returns SHA256("") is not a valid
# fingerprint dimension. It must be classified as inconclusive infrastructure,
# never admitted to either side of an equality comparison.
VM_EXEC() {
    local command_string="$*"
    case "$command_string" in
        *'POSTGRES_APP_DB'*) echo statbus_test ;;
        *'POSTGRES_ADMIN_USER'*) echo postgres ;;
        *'pg_dump --schema-only'*) echo 'CREATE TABLE public.retry_fixture (id integer);' ;;
        *'FROM db.migration'*) echo "$EMPTY_SHA" ;;
        *'FROM public.legal_unit'*) echo "$DATA_SHA" ;;
        *) echo "unexpected VM_EXEC call: $command_string" >&2; return 2 ;;
    esac
}
if capture_db_fingerprint empty-ledger >"$TMP_ROOT/empty-ledger.stdout" 2>"$TMP_ROOT/empty-ledger.stderr"; then
    echo 'FAIL: successful empty-input ledger hash was accepted' >&2
    exit 1
fi
grep -q 'INCONCLUSIVE-INFRA' "$TMP_ROOT/empty-ledger.stderr"
grep -q 'LEDGER.*empty-input SHA-256' "$TMP_ROOT/empty-ledger.stderr"
echo 'PASS: successful empty-input hashes abort fingerprint capture as inconclusive infrastructure'

capture_db_fingerprint() {
    echo "$LEDGER_SHA $LEDGER_SHA $DATA_SHA"
}
if (assert_fingerprint_matches baseline-empty "$LEDGER_SHA $EMPTY_SHA $DATA_SHA") \
    >"$TMP_ROOT/baseline-empty.stdout" 2>"$TMP_ROOT/baseline-empty.stderr"; then
    echo 'FAIL: empty-input hash in baseline fingerprint reached equality comparison' >&2
    exit 1
fi
grep -q 'INCONCLUSIVE-INFRA' "$TMP_ROOT/baseline-empty.stderr"
grep -q 'baseline.*LEDGER.*empty-input SHA-256' "$TMP_ROOT/baseline-empty.stderr"
echo 'PASS: empty-input hashes on either comparison side abort as inconclusive infrastructure'
