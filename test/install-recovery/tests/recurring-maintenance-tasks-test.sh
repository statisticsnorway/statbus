#!/bin/bash
# Offline regression test: an upgrade's end state includes every recurring
# maintenance command the worker seeds (STATBUS-551 AC5). A box whose pending
# row is gone silently stops running that maintenance, so the assertion must
# fail naming the command, and must also fail on a startup-seed failure line.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/install-recovery/lib/assertions.sh"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/statbus-recurring.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
VM_NAME=test-vm

# The guest answers each probe from a fixture file: the registry's recurring
# commands, the commands missing a pending row, and the count of seed-failure
# lines in the worker log. FAIL_PROBE makes one probe unreadable.
VM_EXEC() {
    local cmd="$*"
    case "$cmd" in
        *'NOT EXISTS'*)
            [ "${FAIL_PROBE:-}" != tasks ] || return 1
            cat "$FIXTURE/missing"
            ;;
        *'worker.command_registry WHERE schedule_interval'*)
            [ "${FAIL_PROBE:-}" != registry ] || return 1
            cat "$FIXTURE/expected"
            ;;
        *'docker compose logs'*)
            [ "${FAIL_PROBE:-}" != logs ] || return 1
            cat "$FIXTURE/failed-lines"
            ;;
        *) echo "unexpected VM_EXEC: $cmd" >&2; return 90 ;;
    esac
}

printf '%s\n' detect_stuck_tasks import_job_cleanup task_cleanup > "$FIXTURE/expected"

# 1. Every declared command pending, clean log: pass.
: > "$FIXTURE/missing"
echo 0 > "$FIXTURE/failed-lines"
if ! assert_recurring_maintenance_tasks "$VM_NAME" > "$FIXTURE/out1"; then
    cat "$FIXTURE/out1" >&2
    echo 'FAIL: complete recurring maintenance was rejected' >&2
    exit 1
fi
grep -q 'every recurring maintenance command has a pending row' "$FIXTURE/out1"
grep -q "no 'Failed to seed recurring maintenance tasks' line" "$FIXTURE/out1"
echo 'PASS: complete recurring maintenance with a clean worker log passes'

# 2. One pending row missing: fail naming the command.
printf 'import_job_cleanup\n' > "$FIXTURE/missing"
if assert_recurring_maintenance_tasks "$VM_NAME" > "$FIXTURE/out2"; then
    echo 'FAIL: a recurring command with no pending row was accepted' >&2
    exit 1
fi
grep -q 'no pending row: import_job_cleanup' "$FIXTURE/out2"
echo 'PASS: a missing pending row fails naming the command'

# 3. The startup seed gave up: fail on the worker log line.
: > "$FIXTURE/missing"
echo 1 > "$FIXTURE/failed-lines"
if assert_recurring_maintenance_tasks "$VM_NAME" > "$FIXTURE/out3"; then
    echo 'FAIL: a worker log with a seed failure line was accepted' >&2
    exit 1
fi
grep -q "worker log has 1 'Failed to seed recurring maintenance tasks' line" "$FIXTURE/out3"
echo 'PASS: the startup-seed failure line fails'

# 4. An empty registry must not pass vacuously.
: > "$FIXTURE/expected"
echo 0 > "$FIXTURE/failed-lines"
if assert_recurring_maintenance_tasks "$VM_NAME" > "$FIXTURE/out4"; then
    echo 'FAIL: no declared recurring commands was accepted' >&2
    exit 1
fi
grep -q 'no recurring maintenance commands declared' "$FIXTURE/out4"
echo 'PASS: an empty recurring family fails instead of passing vacuously'

# 5. An unreadable probe fails closed, naming what could not be read — never a
#    green run on a schedule nobody actually observed.
printf '%s\n' detect_stuck_tasks import_job_cleanup task_cleanup > "$FIXTURE/expected"
: > "$FIXTURE/missing"
echo 0 > "$FIXTURE/failed-lines"
for probe in registry tasks logs; do
    case "$probe" in
        registry) what='worker.command_registry' ;;
        tasks) what='worker.tasks' ;;
        logs) what='the worker log' ;;
    esac
    FAIL_PROBE="$probe"
    if assert_recurring_maintenance_tasks "$VM_NAME" > "$FIXTURE/out-$probe"; then
        echo "FAIL: $what unreadable was accepted" >&2
        exit 1
    fi
    grep -q "could not read $what" "$FIXTURE/out-$probe"
    echo "PASS: $what unreadable fails the assertion"
done
unset FAIL_PROBE

# 6. A non-numeric log scan result is an unreadable log, not zero failures.
printf 'not-a-count\n' > "$FIXTURE/failed-lines"
if assert_recurring_maintenance_tasks "$VM_NAME" > "$FIXTURE/out6"; then
    echo 'FAIL: a non-numeric log scan result was accepted' >&2
    exit 1
fi
grep -q 'could not read the worker log scan result' "$FIXTURE/out6"
echo 'PASS: a non-numeric log scan result fails the assertion'
