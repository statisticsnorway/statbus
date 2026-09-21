#!/bin/bash
# Static ordering guard for the c-rollback resurrection fixture repair. The real
# arc still needs the paid VM run, but this catches reintroducing the contradictory
# premise where C snapshots B's intentionally broken auth_status.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
ARC="$ROOT/test/install-recovery/arcs/c-rollback-resurrection-arc.sh"

python3 - "$ARC" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()

capture = text.index("pg_get_functiondef('public.auth_status()'::regprocedure)")
schedule_b = text.index('── schedule B')
park_proved = text.index('✓ B at-target park landed')
restore = text.index('apply_sql_file_with_migration_write_access "$AUTH_STATUS_DEFINITION_PATH"')
pre_c_health = text.index('assert_direct_auth_status_healthy "after park-only fixture cleanup, before C"')
schedule_c = text.index('arc_to "$C_FULL"')

if not (capture < schedule_b < park_proved < restore < pre_c_health < schedule_c):
    raise SystemExit('fixture ordering is not capture canonical body < park B < restore body < prove health < claim C')

for required in (
    'B_ROW_BEFORE_NEUTRALIZE',
    'B_ROW_AFTER_NEUTRALIZE',
    'B_DBMAX_AFTER_NEUTRALIZE',
):
    if required not in text:
        raise SystemExit(f'missing anti-drift assertion: {required}')

if "CREATE OR REPLACE FUNCTION public.auth_status()" in text:
    raise SystemExit('arc hard-codes auth_status instead of restoring the captured source definition')

for required in (
    'docker compose exec -T',
    'PGOPTIONS=-c default_transaction_read_only=off',
):
    if required not in text:
        raise SystemExit(f'fixture cleanup lacks migration-style write access: {required}')

if './sb psql -v ON_ERROR_STOP=1 < "$AUTH_STATUS_DEFINITION_PATH"' in text:
    raise SystemExit('fixture cleanup still uses an ordinary read-only ./sb psql session')

print('PASS: c-rollback fixture repairs only the park fault with write access before C snapshots healthy B')
PY

# Execute the production helper through the real VM_EXEC transport guard. SSH/SCP
# are stubbed, so this is offline, but VM_EXEC and VM_SCRIPT_INLINE are the actual
# harness implementations. A regression to a multi-line VM_EXEC argument must fail
# here before either stub can pretend the command reached a VM.
TMP_ROOT=$(mktemp -d "$ROOT/tmp/crollback-fixture-transport.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
export HCLOUD_TOKEN=offline-test-only
source "$ROOT/test/install-recovery/lib/vm-bootstrap.sh"

SSH_OPTS=(-o OfflineTransportStub=yes)
VM_IP=192.0.2.1
CAPTURED_SCRIPT="$TMP_ROOT/transported-script.sh"
SSH_LOG="$TMP_ROOT/ssh.log"

scp() {
    local arg
    for arg in "$@"; do
        if [ -f "$arg" ]; then
            cp "$arg" "$CAPTURED_SCRIPT"
            return 0
        fi
    done
    echo "stub scp did not receive a local script file: $*" >&2
    return 1
}

ssh() {
    printf '%s\n' "$*" >> "$SSH_LOG"
}

eval "$(sed -n '/^apply_sql_file_with_migration_write_access() {$/,/^}$/p' "$ARC")"
TRANSPORT_ERR="$TMP_ROOT/transport.err"
if ! apply_sql_file_with_migration_write_access "tmp/crollback-auth-status-before-b.sql" 2>"$TRANSPORT_ERR"; then
    cat "$TRANSPORT_ERR" >&2
    echo "fixture helper did not pass the real VM transport guard" >&2
    exit 1
fi
if grep -Fq 'BLOCKED: VM_EXEC was called with a multi-line argument' "$TRANSPORT_ERR"; then
    cat "$TRANSPORT_ERR" >&2
    echo "fixture helper regressed to forbidden multi-line VM_EXEC transport" >&2
    exit 1
fi

test -s "$CAPTURED_SCRIPT"
grep -Fq 'sql_file="$1"' "$CAPTURED_SCRIPT"
grep -Fq 'admin_user=$(./sb dotenv -f .env get POSTGRES_ADMIN_USER)' "$CAPTURED_SCRIPT"
grep -Fq 'PGOPTIONS=-c default_transaction_read_only=off' "$CAPTURED_SCRIPT"
grep -Fq 'psql -X -U "$admin_user" -d "$app_db" -v ON_ERROR_STOP=1 < "$sql_file"' "$CAPTURED_SCRIPT"
grep -Fq 'sudo -i -u statbus -- bash ' "$SSH_LOG"
grep -Fq 'tmp/crollback-auth-status-before-b.sql' "$SSH_LOG"

echo 'PASS: fixture helper crosses the real VM_EXEC guard via transported script bytes and preserves migration write access'
