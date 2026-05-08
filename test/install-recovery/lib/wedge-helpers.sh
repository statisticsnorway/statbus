#!/bin/bash
# wedge-helpers.sh — primitives that simulate specific wedge states inside
# a Multipass VM that already has statbus installed and running.
#
# Each helper takes $vm_name as its first argument. They use $VM_EXEC
# (set by vm-bootstrap.sh's bootstrap_install_test_vm) to operate inside
# the VM as the statbus user.
#
# Source order:
#   source lib/vm-bootstrap.sh
#   source lib/wedge-helpers.sh
#   source lib/assertions.sh

# ─────────────────────────────────────────────────────────────────────────
# simulate_killed_migrate_subprocess <vm_name>
#
# Stage A: Mid-migrate, SIGKILL the migrate-up's psql subprocess. The
# postgres backend lingers running its statement; the parent migrate.Up
# Go process stays alive but the in-flight transaction will eventually
# rollback when postgres notices the dead client.
#
# Mechanism: schedule a slow upgrade, wait for migrate to start, kill the
# psql subprocess. We're testing cleanOrphanSessions Phase 1 catches the
# orphan postgres backend on the next install.
# ─────────────────────────────────────────────────────────────────────────
simulate_killed_migrate_subprocess() {
    local vm_name="$1"
    echo "  [wedge] killing migrate-up psql subprocess on $vm_name"

    # Find the running psql subprocess that's a child of migrate.
    # It's launched via: cli/internal/migrate/migrate.go's runPsqlFile.
    # The OS process is `psql` with file-input.
    $VM_EXEC bash -c '
        for i in $(seq 1 30); do
            PID=$(pgrep -f "psql.*-f.*\.up\.sql" 2>/dev/null | head -1)
            if [ -n "$PID" ]; then
                echo "[wedge] killing psql migrate-subprocess PID=$PID"
                kill -9 "$PID" 2>/dev/null || true
                exit 0
            fi
            sleep 1
        done
        echo "[wedge] no migrate psql subprocess found within 30s — wedge not triggered" >&2
        exit 1
    '
}

# ─────────────────────────────────────────────────────────────────────────
# simulate_pool_exhaustion <vm_name>
#
# Stage B: Open many idle psql sessions until max_connections is at the
# limit. New external connections will fail "FATAL: too many clients".
# cleanOrphanSessions's docker-exec path should still work (peer auth
# inside the container bypasses the pool exhaustion).
# ─────────────────────────────────────────────────────────────────────────
simulate_pool_exhaustion() {
    local vm_name="$1"
    local n="${2:-28}"  # max_connections=30 by default; leave 2 for the killer + docker exec
    echo "  [wedge] opening $n idle psql sessions on $vm_name to saturate pool"

    $VM_EXEC bash -c "
        cd ~/statbus
        for i in \$(seq 1 $n); do
            (./sb psql -c 'SELECT pg_sleep(3600);' >/dev/null 2>&1) &
        done
        sleep 2  # let connections establish
        ACTIVE=\$(./sb psql -t -A -c 'SELECT count(*) FROM pg_stat_activity WHERE datname = current_database();' 2>/dev/null || echo 0)
        echo '[wedge] pool saturated: '\$ACTIVE' connections on test DB'
    "
}

# ─────────────────────────────────────────────────────────────────────────
# simulate_systemd_failed <vm_name>
#
# Stage C: Trip systemd's StartLimitBurst by rapid-cycling the upgrade
# unit. Once tripped, the unit transitions to `failed` state with
# Result=start-limit-hit and won't restart on its own. install ladder
# step 15 should detect this and run reset-failed.
# ─────────────────────────────────────────────────────────────────────────
simulate_systemd_failed() {
    local vm_name="$1"
    local unit="${2:-statbus-upgrade@statbus.service}"
    echo "  [wedge] tripping StartLimitBurst on $unit (12 rapid kill cycles)"

    $VM_EXEC bash -c "
        for i in \$(seq 1 12); do
            systemctl --user start '$unit' 2>/dev/null || true
            sleep 1
            systemctl --user kill '$unit' 2>/dev/null || true
        done
        sleep 2
        STATE=\$(systemctl --user is-active '$unit' 2>&1 || true)
        RESULT=\$(systemctl --user show '$unit' --property=Result --value 2>/dev/null || true)
        echo '[wedge] unit state='\$STATE' result='\$RESULT
    "
}

# ─────────────────────────────────────────────────────────────────────────
# simulate_advisory_zombie_empty_app <vm_name>
#
# Stage D: Open psql with empty application_name, take the migrate_up
# advisory lock, then SIGKILL the script's OS process. The postgres
# backend lingers holding the advisory lock with empty app_name —
# matches PID 9962's exact shape on rune. cleanOrphanSessions Phase 2's
# Go-side PID-liveness check + empty-app-name catch-all should terminate
# the zombie.
# ─────────────────────────────────────────────────────────────────────────
simulate_advisory_zombie_empty_app() {
    local vm_name="$1"
    echo "  [wedge] creating empty-app-name advisory-lock zombie on $vm_name"

    # Use psql with -c that takes the lock and sleeps. The script's PID
    # is captured in the VM, then killed.
    $VM_EXEC bash -c '
        cd ~/statbus
        ./sb psql -c "SET application_name = '\'''\''; SELECT pg_advisory_lock(hashtext('\''migrate_up'\'')); SELECT pg_sleep(3600);" >/dev/null 2>&1 &
        SCRIPT_PID=$!
        sleep 5  # let lock be acquired
        kill -9 $SCRIPT_PID 2>/dev/null || true
        echo "[wedge] killed PID $SCRIPT_PID; postgres backend should still hold advisory lock"
        # Verify: the postgres backend should still be visible
        sleep 2
        ./sb psql -t -A -c "SELECT count(*) FROM pg_locks WHERE locktype='\''advisory'\'' AND granted;" 2>/dev/null
    '
}

# ─────────────────────────────────────────────────────────────────────────
# simulate_worker_busy <vm_name>
#
# Stage E: Queue many heavy worker tasks so the worker is actively
# processing CALL worker.statistical_*_reduce when install runs.
# Validates Fix 8 (worker excluded from advisory_holders count),
# Fix 9 (no false-fail on pool busy-ness),
# Fix 10 (psql-only filter on Phase 1 + leaked).
# ─────────────────────────────────────────────────────────────────────────
simulate_worker_busy() {
    local vm_name="$1"
    local n="${2:-20}"
    echo "  [wedge] queuing $n heavy worker tasks on $vm_name"

    $VM_EXEC bash -c "
        cd ~/statbus
        for i in \$(seq 1 $n); do
            ./sb psql -c \"INSERT INTO worker.tasks (command, payload, queue, priority) VALUES ('statistical_history_reduce', '{}'::jsonb, 'analytics', 100);\" >/dev/null 2>&1
        done
        echo '[wedge] queued '$n' tasks; worker should pick up'
        sleep 3
    "
}

# ─────────────────────────────────────────────────────────────────────────
# simulate_sigkill_upgrade_service <vm_name>
#
# Stage F: Kill the upgrade-service Go process directly with SIGKILL.
# This bypasses systemd's signal handling entirely — the Go process
# never gets a SIGTERM, never runs its rollback() defer chain. Mirrors
# rune's exact failure shape during the original wedge.
#
# Validates the rollback-hole plug Layer 1 (SIGTERM signal handler in
# service.go's Run loop): Layer 1 catches normal systemd-triggered
# SIGTERM gracefully, but a direct kill -9 still bypasses it. Test that
# `recoverFromFlag` at next install correctly handles the resulting
# state (snapshot-restore via Layer 2's --recovery=auto).
# ─────────────────────────────────────────────────────────────────────────
simulate_sigkill_upgrade_service() {
    local vm_name="$1"
    echo "  [wedge] SIGKILL'ing upgrade-service Go process on $vm_name"

    $VM_EXEC bash -c '
        # Find the upgrade-service Go process and kill -9 it.
        for i in $(seq 1 30); do
            PID=$(pgrep -f "sb upgrade service" 2>/dev/null | head -1)
            if [ -n "$PID" ]; then
                echo "[wedge] killing upgrade-service PID=$PID"
                kill -9 "$PID" 2>/dev/null || true
                exit 0
            fi
            sleep 1
        done
        echo "[wedge] no upgrade-service process found within 30s" >&2
        exit 1
    '
}
