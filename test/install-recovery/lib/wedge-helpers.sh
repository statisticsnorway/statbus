#!/bin/bash
# wedge-helpers.sh — primitives that simulate specific wedge states inside
# a Multipass VM that already has statbus installed and running.
#
# Each helper takes $vm_name as its first argument. They use VM_EXEC
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
    VM_EXEC bash -c '
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

    VM_EXEC bash -c "
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

    VM_EXEC bash -c "
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
    VM_EXEC bash -c '
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

    VM_EXEC bash -c "
        cd ~/statbus
        for i in \$(seq 1 $n); do
            ./sb psql -c \"INSERT INTO worker.tasks (command, payload, queue, priority) VALUES ('statistical_history_reduce', '{}'::jsonb, 'analytics', 100);\" >/dev/null 2>&1
        done
        echo '[wedge] queued '$n' tasks; worker should pick up'
        sleep 3
    "
}

# ─────────────────────────────────────────────────────────────────────────
# start_continuous_worker_workload <vm_name> [duration_seconds]
# stop_continuous_worker_workload <vm_name>
#
# Sustained worker contention. Where simulate_worker_busy queues a fixed
# batch (drains in ~30 s), this primitive re-queues analytics tasks on a
# loop for `duration_seconds` (default 300 s) so the worker stays busy
# across the entire failure-injection window. Anchors the R1 race —
# AccessShareLock contention between long-running analytics tasks and
# upgrade-time DDL — by guaranteeing the worker is actually busy when
# the injection fires.
#
# Mechanism: an in-VM background bash loop (kept in a detached tmux
# session so transient ssh drops don't kill it) inserts a
# statistical_history_reduce task into worker.tasks every 2 s. The
# worker picks them up via its analytics queue and runs the reduce —
# each takes seconds, so the queue depth stays positive. The
# corresponding stop primitive removes the marker file the loop checks
# for and waits for the loop to exit cleanly so the VM doesn't carry a
# stale tmux session into cleanup.
#
# Tunables: WORKLOAD_INSERT_INTERVAL_S (default 2). Higher numbers
# reduce queue depth; lower numbers stress the worker harder.
# ─────────────────────────────────────────────────────────────────────────
start_continuous_worker_workload() {
    local vm_name="$1"
    local duration_s="${2:-300}"
    local insert_interval_s="${WORKLOAD_INSERT_INTERVAL_S:-2}"
    echo "  [wedge] starting continuous worker workload on $vm_name (duration=${duration_s}s, interval=${insert_interval_s}s)"

    VM_EXEC bash -c "
        cd ~/statbus
        # Marker file the loop polls for. The stop primitive removes it.
        # Place under /tmp so a VM rebuild wipes it.
        rm -f /tmp/continuous-workload.run
        touch /tmp/continuous-workload.run

        # Detached tmux session named 'continuous-workload' so we can poll
        # for completion in the stop primitive without ssh-port-hopping.
        command -v tmux >/dev/null 2>&1 || sudo apt-get install -y tmux >/dev/null 2>&1 || true
        tmux kill-session -t continuous-workload 2>/dev/null || true
        tmux new-session -d -s continuous-workload \"bash -lc '
            cd ~/statbus
            elapsed=0
            while [ -f /tmp/continuous-workload.run ] && [ \$elapsed -lt $duration_s ]; do
                ./sb psql -c \\\"INSERT INTO worker.tasks (command, payload, queue, priority) VALUES ('\''statistical_history_reduce'\'', '\''{}'\''::jsonb, '\''analytics'\'', 100);\\\" >/dev/null 2>&1 || true
                sleep $insert_interval_s
                elapsed=\$((elapsed + $insert_interval_s))
            done
            rm -f /tmp/continuous-workload.run
            echo done > /tmp/continuous-workload.exit
        '\"
        # Give the loop one cycle to enqueue something measurable before
        # the caller proceeds to whatever wedge it's setting up.
        sleep $((insert_interval_s + 1))
        ./sb psql -t -A -c \"SELECT count(*) FROM worker.tasks WHERE state IN ('pending','processing');\" 2>/dev/null | xargs -I{} echo '  [wedge] continuous workload running: queue depth {}'
    "
}

stop_continuous_worker_workload() {
    local vm_name="$1"
    local max_wait_s="${1:-30}"
    echo "  [wedge] stopping continuous worker workload on $vm_name"

    VM_EXEC bash -c "
        # Signal the loop to exit cleanly. The loop polls every <interval> s.
        rm -f /tmp/continuous-workload.run

        # Wait for the loop's exit sentinel (written when it returns).
        # Caps at $max_wait_s so a wedged loop can't block scenario cleanup.
        elapsed=0
        while [ ! -f /tmp/continuous-workload.exit ] && [ \$elapsed -lt $max_wait_s ]; do
            sleep 1
            elapsed=\$((elapsed + 1))
        done

        # Tear down the tmux session regardless — if the loop didn't exit
        # cleanly we still don't want a stale session hanging around.
        tmux kill-session -t continuous-workload 2>/dev/null || true
        rm -f /tmp/continuous-workload.exit
        echo '  [wedge] continuous workload stopped (elapsed='\$elapsed's)'
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
# state (snapshot-restore via the unified forward-then-restore path).
# ─────────────────────────────────────────────────────────────────────────
simulate_sigkill_upgrade_service() {
    local vm_name="$1"
    echo "  [wedge] SIGKILL'ing upgrade-service Go process on $vm_name"

    VM_EXEC bash -c '
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

# ─────────────────────────────────────────────────────────────────────────
# wait_for_inject_stall_ready <vm_name> <release_file>
#
# Polls inside the VM for the inject.StallHere primitive to be active at
# the canonical migrate-up site. "Active" means:
#
#   (a) the release file (passed to STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE)
#       exists on disk — sanity check that we set it up correctly, and
#   (b) at least one `./sb migrate up` subprocess is running, and
#   (c) the process has been alive long enough to have plausibly reached
#       runUp's per-migration loop.
#
# Returns 0 once (a)+(b)+(c) hold continuously for one poll interval;
# returns 1 after MAX_WAIT_S without observing.
#
# Note: the canonical-case stalls fire AFTER a migration's outer
# transaction commits — so once the migrate subprocess has been alive
# in the stall state for >5 s, the partial-state RED has been achieved
# (the first pending migration is committed; its db.migration row is
# missing). Callers should then send SIGKILL to the chosen target PID.
# ─────────────────────────────────────────────────────────────────────────
wait_for_inject_stall_ready() {
    local vm_name="$1"
    local release_file="$2"
    local max_wait_s="${3:-300}"
    local poll_s=3
    local stable_s=10
    local stable_since=""
    local elapsed=0

    echo "  [wedge] waiting for inject.StallHere to be active on $vm_name"
    echo "          release_file=$release_file, max_wait=${max_wait_s}s"

    while [ "$elapsed" -lt "$max_wait_s" ]; do
        # Bundle the three checks into one ssh round-trip so a flaky link
        # doesn't make us miss the window.
        local probe
        probe=$(VM_EXEC bash -c "
            REL='$release_file'
            REL_PRESENT=0; [ -f \"\$REL\" ] && REL_PRESENT=1
            MIGRATE_PID=\$(pgrep -f '/sb migrate up' 2>/dev/null | head -1 || echo '')
            STARTED_AT=''
            if [ -n \"\$MIGRATE_PID\" ]; then
                STARTED_AT=\$(ps -o lstart= -p \"\$MIGRATE_PID\" 2>/dev/null || echo '')
            fi
            echo \"REL_PRESENT=\$REL_PRESENT MIGRATE_PID=\$MIGRATE_PID STARTED_AT=\$STARTED_AT\"
        " 2>/dev/null || echo "REL_PRESENT=? MIGRATE_PID= STARTED_AT=")

        local rel_present migrate_pid
        rel_present=$(echo "$probe" | sed -n 's/.*REL_PRESENT=\([^ ]*\).*/\1/p')
        migrate_pid=$(echo "$probe" | sed -n 's/.*MIGRATE_PID=\([^ ]*\).*/\1/p')

        if [ "$rel_present" = "1" ] && [ -n "$migrate_pid" ]; then
            if [ -z "$stable_since" ]; then
                stable_since="$elapsed"
                echo "  [wedge] migrate subprocess detected (PID=$migrate_pid) — confirming stall stability"
            elif [ $((elapsed - stable_since)) -ge "$stable_s" ]; then
                echo "  [wedge] stall confirmed: migrate PID=$migrate_pid alive for $((elapsed - stable_since))s with release file present"
                # Echo the PID on stdout for the caller to capture.
                echo "$migrate_pid"
                return 0
            fi
        else
            if [ -n "$stable_since" ]; then
                echo "  [wedge] stall stability broken (rel=$rel_present pid=$migrate_pid) — resetting"
            fi
            stable_since=""
        fi
        sleep "$poll_s"
        elapsed=$((elapsed + poll_s))
    done

    echo "  [wedge] timed out after ${max_wait_s}s waiting for stall" >&2
    return 1
}

# ─────────────────────────────────────────────────────────────────────────
# kill_pid_in_vm <vm_name> <pid> [signal]
#
# Send `signal` (default KILL) to `pid` inside the VM. Wraps the ssh
# round-trip so scenario scripts read cleanly.
# ─────────────────────────────────────────────────────────────────────────
kill_pid_in_vm() {
    local vm_name="$1"
    local pid="$2"
    local sig="${3:-KILL}"
    echo "  [wedge] kill -$sig $pid on $vm_name"
    VM_EXEC bash -c "kill -$sig $pid 2>&1 || true"
}

# ─────────────────────────────────────────────────────────────────────────
# pgrep_upgrade_service_parent <vm_name>
#
# Returns the PID of the upgrade-service process (the Go binary's
# `executeUpgrade` parent) running install-dispatched inside the VM. The
# install-dispatched path lives in `./sb install`'s process, NOT in the
# systemd `./sb upgrade service`. We look for the most recently started
# `./sb install` process that is NOT a child of bash (i.e. the actual Go
# binary, not the wrapper shell).
# ─────────────────────────────────────────────────────────────────────────
pgrep_upgrade_service_parent() {
    local vm_name="$1"
    VM_EXEC bash -c "pgrep -nf '/sb install' 2>/dev/null || true"
}

# ─────────────────────────────────────────────────────────────────────────
# remove_release_file_in_vm <vm_name> <release_file>
#
# Cleanup helper. The harness writes the release file before triggering
# the stalling install, and removes it once the relevant processes are
# dead. Idempotent — safe to call when the file is already gone.
# ─────────────────────────────────────────────────────────────────────────
remove_release_file_in_vm() {
    local vm_name="$1"
    local release_file="$2"
    VM_EXEC bash -c "rm -f '$release_file' 2>&1 || true"
}
