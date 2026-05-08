#!/bin/bash
# assertions.sh — assertion helpers for install-recovery scenario scripts.
#
# Each assertion: prints a one-line PASS / FAIL diagnostic and returns
# 0 on pass, 1 on fail. Scenario scripts chain assertions and `set -e`
# bails on the first failure.
#
# Source AFTER vm-bootstrap.sh — relies on $VM_EXEC being set.

# Test that the app's REST endpoint responds 2xx/3xx within ~50s.
# Slot=test → port 3010 (from vm-bootstrap's env-config). Override
# port via $HEALTH_PORT if needed.
assert_health_passes() {
    local vm_name="$1"
    local port="${HEALTH_PORT:-3010}"
    local i http_code

    for i in $(seq 1 10); do
        http_code=$($VM_EXEC bash -c "curl -s http://127.0.0.1:${port}/rest/ -o /dev/null -w '%{http_code}'" 2>/dev/null || echo "000")
        if echo "$http_code" | grep -q "^[23]"; then
            echo "  ✓ health check passed (attempt $i, code=$http_code)"
            return 0
        fi
        echo "  … waiting for app on $vm_name:$port (attempt $i/10, code=$http_code)"
        sleep 5
    done
    echo "  ✗ health check FAILED after 10 attempts"
    return 1
}

# Verify the latest public.upgrade row is in the expected state.
# Useful states: 'completed', 'rolled_back', 'failed', 'in_progress'.
assert_upgrade_row_state() {
    local vm_name="$1"
    local expected_state="$2"
    local actual

    actual=$($VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' ')
    if [ "$actual" = "$expected_state" ]; then
        echo "  ✓ latest upgrade row state = '$expected_state'"
        return 0
    fi
    echo "  ✗ upgrade row state mismatch: expected='$expected_state' actual='$actual'"
    return 1
}

# Verify the systemd upgrade-service unit is in the expected ActiveState.
# Default unit: statbus-upgrade@statbus.service. Default state: active.
assert_systemd_active() {
    local vm_name="$1"
    local unit="${2:-statbus-upgrade@statbus.service}"
    local expected_state="${3:-active}"
    local actual

    actual=$($VM_EXEC systemctl --user is-active "$unit" 2>/dev/null | head -1 || echo "unknown")
    if [ "$actual" = "$expected_state" ]; then
        echo "  ✓ unit $unit is $expected_state"
        return 0
    fi
    echo "  ✗ unit $unit state mismatch: expected='$expected_state' actual='$actual'"
    return 1
}

# Verify there are NO orphan pre-upgrade-* backup directories left in
# ~/statbus-backups/. After a successful recovery, the executeUpgrade-
# layer cleanup (Layer 3 of the rollback hole plug) should have removed
# the pre-upgrade backup that was taken before the upgrade.
assert_no_orphan_backup() {
    local vm_name="$1"
    local count

    count=$($VM_EXEC bash -c 'ls -d ~/statbus-backups/pre-upgrade-* 2>/dev/null | wc -l' 2>/dev/null | tr -d ' ' || echo "0")
    if [ "$count" = "0" ]; then
        echo "  ✓ no orphan pre-upgrade-* backups in ~/statbus-backups/"
        return 0
    fi
    echo "  ✗ orphan backup(s) found ($count): $($VM_EXEC bash -c 'ls -d ~/statbus-backups/pre-upgrade-*' 2>/dev/null | tr '\n' ' ')"
    return 1
}

# Verify a specific migration version is recorded as applied.
assert_db_migration_recorded() {
    local vm_name="$1"
    local version="$2"
    local count

    count=$($VM_EXEC bash -c "cd ~/statbus && echo 'SELECT count(*) FROM db.migration WHERE version = $version;' | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "0")
    if [ "$count" = "1" ]; then
        echo "  ✓ migration $version recorded in db.migration"
        return 0
    fi
    echo "  ✗ migration $version NOT recorded (count=$count)"
    return 1
}

# Verify the install ran cleanly through step 9 (Database sessions).
# Step 9 is where bool-text and worker-exclusion bugs caused failure.
# Check by tailing the install log for the "[9/15] Database sessions DONE"
# or "OK" line, NOT "FAILED".
assert_step9_completed() {
    local vm_name="$1"
    local log_file="${HARNESS_ROOT}/tmp/install-recovery-${vm_name}-install.log"

    if [ ! -f "$log_file" ]; then
        echo "  ✗ install log not found: $log_file"
        return 1
    fi
    if grep -E "^\[9/15\] Database sessions\s+(OK|DONE)" "$log_file" >/dev/null; then
        echo "  ✓ step 9 (Database sessions) completed"
        return 0
    fi
    if grep -E "^\[9/15\] Database sessions\s+FAILED" "$log_file" >/dev/null; then
        echo "  ✗ step 9 FAILED — bool-text or worker-exclusion class regression"
        return 1
    fi
    echo "  ✗ step 9 status unclear in log $log_file"
    return 1
}

# Verify that all 15 install steps reached completion (i.e. step 15 ran).
# Step 15 is where the systemd reset-failed lives.
assert_step15_completed() {
    local vm_name="$1"
    local log_file="${HARNESS_ROOT}/tmp/install-recovery-${vm_name}-install.log"

    if [ ! -f "$log_file" ]; then
        echo "  ✗ install log not found: $log_file"
        return 1
    fi
    if grep -E "^\[15/15\] Upgrade service\s+(OK|DONE)" "$log_file" >/dev/null; then
        echo "  ✓ step 15 (Upgrade service) completed"
        return 0
    fi
    echo "  ✗ step 15 did NOT complete — install bailed before reaching it"
    return 1
}
