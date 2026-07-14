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

    # ssh-STDIN transport, NOT VM_EXEC's printf %q: the multi-line script rides
    # stdin so its newlines/quotes/$() survive every quoting layer untouched; only
    # the fixed `bash -c 'cd ~/statbus && bash'` (the proven assertions.sh pattern)
    # hits the command line. printf %q collapsed the for-loop newlines →
    # "syntax error near unexpected token `do'" (run 27168472969); the shared
    # VM_EXEC base64 rewrite broke 0/18 and was reverted, so this stays per-scenario
    # (this function is used only by 5-install-stage-b-pool-exhaustion).
    #
    # CRITICAL: connect as the NON-SUPERUSER app role (POSTGRES_APP_USER), NOT via
    # `./sb psql` (which uses POSTGRES_ADMIN_USER=postgres = superuser).
    # Superuser connections count against superuser_reserved_connections (default 3),
    # which are the exact reserved slots that cleanOrphanSessions' docker-exec peer-
    # auth bypass relies on being free (install.go). Filling them with superuser idle
    # sessions blocks the bypass itself — the wedge proves the wrong failure.
    # A real Stage-B exhaustion is non-superuser (app/worker/rest) connections, which
    # cap at max_connections - superuser_reserved, leaving those reserved slots FREE.
    local _wedge
    _wedge=$(mktemp)
    {
        echo "N=$n"
        cat <<'WEDGE'
# Source env to get app-user credentials.  The heredoc delimiter is quoted so
# no local expansion occurs; $POSTGRES_APP_* etc. expand on the remote after source.
set -a
[ -f .env ] && source .env 2>/dev/null || true
[ -f .env.credentials ] && source .env.credentials 2>/dev/null || true
set +a
for i in $(seq 1 $N); do
    (docker compose exec -T -e "PGPASSWORD=$POSTGRES_APP_PASSWORD" db psql -U "$POSTGRES_APP_USER" -d "$POSTGRES_APP_DB" -c 'SELECT pg_sleep(3600);' >/dev/null 2>&1) &
done
sleep 2  # let connections establish
ACTIVE=$(./sb psql -t -A -c 'SELECT count(*) FROM pg_stat_activity WHERE datname = current_database();' 2>/dev/null || echo 0)
echo "[wedge] pool saturated (app-user, non-superuser): $ACTIVE connections on test DB"
WEDGE
    } > "$_wedge"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "sudo -i -u statbus bash -c 'cd ~/statbus && bash'" < "$_wedge"
    rm -f "$_wedge"
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

    # ssh-STDIN transport (see simulate_pool_exhaustion) — multi-line script via
    # stdin; used only by 5-install-stage-c-systemd-failed.
    local _wedge
    _wedge=$(mktemp)
    {
        echo "U='$unit'"
        cat <<'WEDGE'
for i in $(seq 1 12); do
    systemctl --user start "$U" 2>/dev/null || true
    sleep 1
    systemctl --user kill "$U" 2>/dev/null || true
done
sleep 2
STATE=$(systemctl --user is-active "$U" 2>&1 || true)
RESULT=$(systemctl --user show "$U" --property=Result --value 2>/dev/null || true)
echo "[wedge] unit state=$STATE result=$RESULT"
WEDGE
    } > "$_wedge"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "sudo -i -u statbus bash -c 'cd ~/statbus && bash'" < "$_wedge"
    rm -f "$_wedge"
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

    # ssh-STDIN transport (see simulate_pool_exhaustion): VM_EXEC's printf %q would collapse
    # the multi-line script (dash $'...\n...') and mangle it. Riding stdin also lets the SQL
    # use normal single quotes (no '\'' escaping) since the quoted heredoc passes everything
    # verbatim; $SCRIPT_PID / $! expand on the remote.
    local _wedge
    _wedge=$(mktemp)
    cat > "$_wedge" <<'WEDGE'
./sb psql -c "SET application_name = ''; SELECT pg_advisory_lock(hashtext('migrate_up')); SELECT pg_sleep(3600);" >/dev/null 2>&1 &
SCRIPT_PID=$!
sleep 5  # let lock be acquired
kill -9 $SCRIPT_PID 2>/dev/null || true
echo "[wedge] killed PID $SCRIPT_PID; postgres backend should still hold advisory lock"
sleep 2
./sb psql -t -A -c "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND granted;" 2>/dev/null
WEDGE
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "sudo -i -u statbus bash -c 'cd ~/statbus && bash'" < "$_wedge"
    rm -f "$_wedge"
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

    # ssh-STDIN transport (see simulate_pool_exhaustion) — multi-line script via
    # stdin; used only by 5-install-stage-e-worker-busy.
    local _wedge
    _wedge=$(mktemp)
    {
        echo "N=$n"
        cat <<'WEDGE'
for i in $(seq 1 $N); do
    # column list: (command, payload) only — no 'queue' column exists in worker.tasks.
    # payload MUST include {"command":"..."} to satisfy the consistent_command_in_payload CHECK.
    ./sb psql -c "INSERT INTO worker.tasks (command, payload) VALUES ('statistical_history_reduce', '{\"command\":\"statistical_history_reduce\"}'::jsonb);" >/dev/null 2>&1
done
echo "[wedge] queued $N tasks; worker should pick up"
sleep 3
WEDGE
    } > "$_wedge"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "sudo -i -u statbus bash -c 'cd ~/statbus && bash'" < "$_wedge"
    rm -f "$_wedge"
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

    # VM_SCRIPT_INLINE (quoted heredoc) per the VM_EXEC multi-line guard: the
    # body ships verbatim to the VM; the loop is written there as its OWN file
    # so tmux runs a FILE, never a locally-quoted string (the old triple-nested
    # bash -c/tmux/bash -lc quoting is exactly what the guard exists to end).
    VM_SCRIPT_INLINE start-continuous-workload "$duration_s" "$insert_interval_s" << 'SCRIPT'
#!/bin/bash
set -euo pipefail
duration_s="$1"
insert_interval_s="$2"
cd ~/statbus
# Marker file the loop polls for. The stop primitive removes it.
# Placed under /tmp so a VM rebuild wipes it.
rm -f /tmp/continuous-workload.run /tmp/continuous-workload.exit
touch /tmp/continuous-workload.run
# The loop body, materialized remotely; the UNQUOTED heredoc delimiter is
# deliberate — $duration_s/$insert_interval_s interpolate HERE (remote), while
# \$elapsed stays literal for the loop's own runtime.
cat > /tmp/continuous-workload-loop.sh << LOOP
#!/bin/bash
cd ~/statbus
elapsed=0
while [ -f /tmp/continuous-workload.run ] && [ "\$elapsed" -lt $duration_s ]; do
    ./sb psql -c "INSERT INTO worker.tasks (command, payload) VALUES ('statistical_history_reduce', jsonb_build_object('command', 'statistical_history_reduce'));" >/dev/null 2>&1 || true
    sleep $insert_interval_s
    elapsed=\$((elapsed + $insert_interval_s))
done
rm -f /tmp/continuous-workload.run
echo done > /tmp/continuous-workload.exit
LOOP
chmod 0755 /tmp/continuous-workload-loop.sh
# Detached tmux session named 'continuous-workload' so the stop primitive can
# poll for completion without ssh-port-hopping.
command -v tmux >/dev/null 2>&1 || sudo apt-get install -y tmux >/dev/null 2>&1 || true
tmux kill-session -t continuous-workload 2>/dev/null || true
tmux new-session -d -s continuous-workload /tmp/continuous-workload-loop.sh
# Give the loop one cycle to enqueue something measurable before the caller
# proceeds to whatever wedge it is setting up.
sleep $((insert_interval_s + 1))
./sb psql -t -A -c "SELECT count(*) FROM worker.tasks WHERE state IN ('pending','processing');" 2>/dev/null | xargs -I{} echo "  [wedge] continuous workload running: queue depth {}"
SCRIPT
}

stop_continuous_worker_workload() {
    local vm_name="$1"
    # NB: was "${1:-30}" — a pre-existing bug that read the VM NAME as the
    # wait cap (non-numeric, so the remote [ -lt ] test errored every poll).
    local max_wait_s="${2:-30}"
    echo "  [wedge] stopping continuous worker workload on $vm_name"

    VM_SCRIPT_INLINE stop-continuous-workload "$max_wait_s" << 'SCRIPT'
#!/bin/bash
set -euo pipefail
max_wait_s="$1"
# Signal the loop to exit cleanly. The loop polls every <interval> s.
rm -f /tmp/continuous-workload.run
# Wait for the loop's exit sentinel (written when it returns); capped so a
# wedged loop cannot block scenario cleanup.
elapsed=0
while [ ! -f /tmp/continuous-workload.exit ] && [ "$elapsed" -lt "$max_wait_s" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done
# Tear down the tmux session regardless — if the loop did not exit cleanly we
# still do not want a stale session hanging around.
tmux kill-session -t continuous-workload 2>/dev/null || true
rm -f /tmp/continuous-workload.exit /tmp/continuous-workload-loop.sh
echo "  [wedge] continuous workload stopped (elapsed=${elapsed}s)"
SCRIPT
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
# Note: what "stall confirmed" MEANS depends on the armed inject class —
# this helper only detects "a migrate subprocess is parked with the
# release file present":
#   - kill-window classes (e.g. migrate-subprocess-killed-after-commit-
#     before-recorded) stall AFTER a migration's outer transaction
#     commits — the partial-state RED is achieved (migration committed,
#     db.migration row missing) and the caller then SIGKILLs the PID.
#   - migration-slower-than-systemd-unit-timeout (C12 / STATBUS-012)
#     stalls in runPsqlFile BEFORE psql is invoked — nothing has
#     committed; the caller HOLDS the stall past WatchdogSec and then
#     removes the release file (no kill).
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
# wait_for_midtx_stall_ready <vm_name> [max_wait_s]
#
# Variant of wait_for_inject_stall_ready for the mid-tx-kill scenario
# (3-postswap-mid-tx-kill). On the INLINE dispatch path (./sb install →
# executeUpgrade), migrations run within the parent Go binary — there is NO
# separate `./sb migrate up` subprocess for pgrep to find. Instead,
# inject.MidTxPauseSQL splices a SELECT pg_sleep(3600) into the migration's
# transaction; the parked psql backend is detectable via pg_stat_activity
# (application_name LIKE 'statbus-migrate-sql%', query ILIKE '%pg_sleep%').
#
# Returns 0 once such a backend is stable for stable_s seconds; echoes its
# OS PID (from pg_stat_activity.pid, or the host-side docker-exec PID when
# in docker mode) for the caller to SIGKILL.
# Returns 1 after max_wait_s without observing.
# ─────────────────────────────────────────────────────────────────────────
wait_for_midtx_stall_ready() {
    local vm_name="$1"
    local max_wait_s="${2:-300}"
    local poll_s=3
    local stable_s=5
    local stable_since=""
    local elapsed=0

    echo "  [wedge] waiting for mid-tx psql backend to park on $vm_name" >&2
    echo "          max_wait=${max_wait_s}s" >&2

    while [ "$elapsed" -lt "$max_wait_s" ]; do
        # Query pg_stat_activity for the parked migration backend: the injected
        # pg_sleep is running inside the migration's outer BEGIN...END transaction.
        # application_name is 'statbus-migrate-sql-<pid>' (migrateSubprocessAppName).
        local db_pid
        db_pid=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT pid FROM pg_stat_activity WHERE application_name LIKE 'statbus-migrate-sql%' AND query ILIKE '%pg_sleep%' AND state = 'active' LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "")

        if [ -n "$db_pid" ]; then
            if [ -z "$stable_since" ]; then
                stable_since="$elapsed"
                echo "  [wedge] mid-tx backend detected (db-pid=$db_pid) — confirming stability" >&2
            elif [ $((elapsed - stable_since)) -ge "$stable_s" ]; then
                echo "  [wedge] mid-tx stall confirmed (idle for $((elapsed - stable_since))s)" >&2
                # Find the host-side process PID to SIGKILL.  In docker exec mode the
                # psql runs inside the container; the host-side wrapper is `docker compose
                # exec -T ... db psql`.  pgrep for that; fall back to db_pid (host-psql mode
                # where pg_stat_activity.pid IS the host OS PID).
                local host_pid
                host_pid=$(VM_EXEC bash -c "pgrep -f 'docker.*exec.*-T.*db.*psql' 2>/dev/null | head -1 || echo ''" 2>/dev/null | tr -d ' \r\n' || echo "")
                if [ -z "$host_pid" ]; then
                    host_pid="$db_pid"
                    echo "  [wedge] (host-psql mode: using db-pid as migrate subprocess PID)" >&2
                fi
                echo "  [wedge] stall confirmed: migrate host-PID=$host_pid db-pid=$db_pid" >&2
                echo "$host_pid"
                return 0
            fi
        else
            if [ -n "$stable_since" ]; then
                echo "  [wedge] stability broken — resetting" >&2
            fi
            stable_since=""
        fi
        sleep "$poll_s"
        elapsed=$((elapsed + poll_s))
    done

    echo "  [wedge] timed out after ${max_wait_s}s waiting for mid-tx backend" >&2
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

# ─────────────────────────────────────────────────────────────────────────
# write_preswap_wedge <vm_name> <commit_sha> [from_version]
#
# Synthesises the crash state that v2026.05.2's executeUpgrade left behind
# when the process was killed AFTER `git checkout <commitSHA>` but BEFORE
# the binary swap. This is the pre-STATBUS-060 preswap-checkout window:
#
#   1. public.upgrade row in state='in_progress', from_commit_version=<from_version>
#      (mirrors executeUpgrade's scheduled→in_progress claim UPDATE in
#      ExecuteUpgradeInline / executeScheduled).
#   2. All services stopped (docker compose stop was called for backup).
#   3. ~/statbus-backups/pre-upgrade-active/ dir created (managed backup dir;
#      backup_path="" in the PreSwap flag so restoreDatabase is a no-op —
#      the minimal empty dir satisfies assert_no_orphan_backup's exclusion of
#      managed dirs, mirrors the product's backupActiveName naming).
#   4. `git branch -f pre-upgrade HEAD` pointing at OLD_COMMIT (mirrors
#      executeUpgrade:3256 "Pin the pre-upgrade commit … BEFORE destructive steps").
#   5. `git fetch` + `git checkout <commitSHA>` done (old v2026.05.2 behavior,
#      removed by STATBUS-060 — working tree IS at the target commit, not source).
#   6. Flag file at ~/statbus/tmp/upgrade-in-progress.json with
#      holder="service", phase="" (PreSwap / omitempty), backup_path absent.
#   7. ./sb binary UNCHANGED (still the INSTALL_VERSION binary — the binary
#      swap never happened).
#
# CALLER ORDERING IS LOAD-BEARING:
#   Call fabricate_scheduled_upgrade_row BEFORE this helper (DB must be up
#   to transition the row to in_progress). The helper stops the DB as
#   step 2, so no SQL is possible after it returns.
#
# PARAMETERS:
#   vm_name      — target VM (used via VM_EXEC and SSH_OPTS/VM_IP)
#   commit_sha   — target commit SHA (HEAD_LOCAL; the commit we're upgrading TO)
#   from_version — optional; the bare version string to record in
#                  public.upgrade.from_commit_version. Pass d.version's format —
#                  v-stripped (e.g. "2026.05.2" for the release v2026.05.2),
#                  matching ExecuteUpgradeInline / executeScheduled which write
#                  d.version verbatim. from_commit_version is display-only; recovery
#                  restores via the pinned pre-upgrade branch (STATBUS-077 removed the
#                  from_commit_sha column — all recovery is branch-based). When
#                  empty/omitted, NULL.
#
# Returns 0 on success; non-zero on failure.
# ─────────────────────────────────────────────────────────────────────────
write_preswap_wedge() {
    local vm_name="$1"
    local commit_sha="$2"   # target commit SHA (HEAD_LOCAL)
    local from_version="${3:-}"  # source version for from_commit_version (optional)

    echo "  [wedge] writing v2026.05.2-style preswap crash state on $vm_name"
    echo "          target commit:       $(echo "$commit_sha" | cut -c1-8) (working tree WILL be at target — old checkout behavior)"
    echo "          from_commit_version: ${from_version:-(empty→NULL)}"

    # ── step 1: transition upgrade row to in_progress and capture id ──
    # DB is still up at this point (fabricate_scheduled_upgrade_row was called
    # by the caller before invoking this helper). UPDATE → RETURNING id.
    # CLAUDE.md: never echo SQL over SSH — write to a local tmp file, scp to VM.
    local sql_file row_id sql_result
    sql_file=$(mktemp /tmp/harness-wedge-inprogress-XXXXXX.sql)
    # Single-line SQL avoids newline/quoting collapse in printf; psql -t -A gives tuples-only.
    # NULLIF('', '') normalises an absent from_version to NULL; a real SHA/tag is stored as-is.
    # Mirrors executeUpgrade's scheduled→in_progress claim UPDATE
    # (ExecuteUpgradeInline / executeScheduled) which writes d.version verbatim;
    # from_commit_version is display-only; recovery restores via the pinned
    # pre-upgrade branch (STATBUS-077 removed the from_commit_sha column).
    printf "UPDATE public.upgrade SET state = 'in_progress'::public.upgrade_state, started_at = now(), from_commit_version = NULLIF('%s', '') WHERE commit_sha = '%s' AND state = 'scheduled'::public.upgrade_state RETURNING id;\n" \
        "$from_version" "$commit_sha" > "$sql_file"
    chmod 644 "$sql_file"
    scp -O "${SSH_OPTS[@]}" "$sql_file" root@"$VM_IP":/tmp/harness-wedge-inprogress.sql >/dev/null
    rm -f "$sql_file"
    local sql_rc=0
    sql_result=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A < /tmp/harness-wedge-inprogress.sql' && rm -f /tmp/harness-wedge-inprogress.sql" \
        2>&1) || sql_rc=$?
    if [ "$sql_rc" -ne 0 ]; then
        echo "  ✗ write_preswap_wedge: UPDATE to in_progress failed (rc=$sql_rc):" >&2
        echo "$sql_result" >&2
        return 1
    fi
    row_id=$(echo "$sql_result" | grep -E '^[0-9]+$' | tr -d ' \r\n' || echo "")
    if [ -z "$row_id" ]; then
        echo "  ✗ write_preswap_wedge: could not parse row id from psql output: $sql_result" >&2
        return 1
    fi
    echo "  [wedge] upgrade row id=$row_id transitioned to in_progress"

    # ── steps 2–7: stop services, create backup dir, git ops, write flag ──
    # Transport: write the script body to a local temp file and scp it to the
    # VM (same gold-standard pattern as seed_pre_upgrade_snapshot). The outer
    # heredoc is UNQUOTED so ${commit_sha} and ${row_id} expand locally and
    # land in the remote script as literal values. Remote-side subshells
    # (\$(…)) are protected by backslash from local expansion.
    local wedge_script
    wedge_script=$(mktemp /tmp/harness-wedge-preswap-XXXXXX.sh)
    cat > "$wedge_script" << WEDGE_SCRIPT
set -euo pipefail
cd ~/statbus
COMMIT_SHA="${commit_sha}"
ROW_ID="${row_id}"

# Step 2: stop all services — mirrors v2026.05.2's executeUpgrade stopping
# the DB for a consistent volume snapshot (service.go:3080 docker compose stop).
echo "    [wedge] stopping docker services..."
docker compose stop >/dev/null 2>&1 || true

# Step 3: create the managed backup dir. v2026.05.2 completed its rsync into
# a per-stamp dir before renaming to pre-upgrade-active; we create a minimal
# empty managed dir because (a) backup_path="" in the PreSwap flag so
# restoreDatabase is a no-op and needs no volume data, and (b) the managed
# name pre-upgrade-active is excluded by assert_no_orphan_backup (mirrors
# Go's isManagedBackupDir / backupActiveName = "pre-upgrade-active").
echo "    [wedge] creating ~/statbus-backups/pre-upgrade-active/ (managed backup dir, minimal)..."
mkdir -p ~/statbus-backups/pre-upgrade-active

# Step 4: pin the pre-upgrade branch to OLD_COMMIT (current HEAD, the source
# commit). Mirrors executeUpgrade:3256 "git branch -f pre-upgrade HEAD".
# restoreGitStateFn falls back to this branch when previousVersion does not
# resolve, so it MUST point at OLD_COMMIT before the working tree advances.
echo "    [wedge] pinning pre-upgrade branch to \$(git rev-parse --short HEAD) (OLD_COMMIT)..."
git branch -f pre-upgrade HEAD

# Step 5: fetch target commit objects — mirrors executeUpgrade:3273.
echo "    [wedge] fetching target commit objects \${COMMIT_SHA:0:8}..."
if ! git cat-file -e "\$COMMIT_SHA" 2>/dev/null; then
    git fetch --depth 1 origin "\$COMMIT_SHA"
fi

# Step 6: checkout target commit — this IS the pre-STATBUS-060 behavior.
# v2026.05.2's executeUpgrade:3278 did "git checkout commitSHA" here.
# STATBUS-060 removed this step; on HEAD the working tree stays at OLD_COMMIT.
# This is the load-bearing difference: the old binary materialised target-compose
# before the kill, which prevented recovery (EnsureDBUp parsed the target's
# docker-compose files, hit REST_ADMIN_BIND_ADDRESS missing from .env, failed).
echo "    [wedge] checking out target commit (pre-STATBUS-060 old behavior)..."
git -c advice.detachedHead=false checkout "\$COMMIT_SHA"
echo "    [wedge] working tree now at: \$(git rev-parse --short HEAD)"

# Step 7: write the flag JSON. Mirrors the on-disk file that v2026.05.2's
# writeUpgradeFlag (service.go:381) would have written. Fields:
#   id          — upgrade row id (required; recoveryRollback queries by id)
#   commit_sha  — target SHA (required; flag.Label() display)
#   pid         — any value; the process is "dead" (recovery checks liveness,
#                 treats dead PID as StateCrashedUpgrade)
#   started_at  — RFC3339 timestamp
#   invoked_by  — informational; "harness:legacy-wedge" for traceability
#   trigger     — "scheduled" (mirrors fabricate_scheduled_upgrade_row context)
#   holder      — "service" (HolderService; executeUpgrade always writes this)
# Absent fields (omitempty): phase (= "" = PreSwap), backup_path, recreate.
echo "    [wedge] writing flag JSON (id=\$ROW_ID, holder=service, phase=PreSwap)..."
mkdir -p tmp
NOW_ISO=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{
  "id": %s,
  "commit_sha": "%s",
  "pid": 12345,
  "started_at": "%s",
  "invoked_by": "harness:legacy-wedge",
  "trigger": "scheduled",
  "holder": "service"
}
' "\$ROW_ID" "\$COMMIT_SHA" "\$NOW_ISO" > tmp/upgrade-in-progress.json
echo "    [wedge] flag written:"
cat tmp/upgrade-in-progress.json
WEDGE_SCRIPT

    chmod 644 "$wedge_script"
    scp -O "${SSH_OPTS[@]}" "$wedge_script" root@"$VM_IP":/tmp/harness-wedge-preswap.sh >/dev/null
    rm -f "$wedge_script"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" 'chmod 0644 /tmp/harness-wedge-preswap.sh'
    local rc=0
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" 'sudo -i -u statbus bash /tmp/harness-wedge-preswap.sh' || rc=$?
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" 'rm -f /tmp/harness-wedge-preswap.sh' >/dev/null 2>&1 || true
    if [ "$rc" -ne 0 ]; then
        echo "  ✗ write_preswap_wedge: remote script failed (exit $rc)" >&2
        return 1
    fi
    echo "  ✓ preswap wedge written (row=$row_id, WT=target-commit, binary=INSTALL_VERSION, flag=PreSwap)"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# quiesce_upgrade_service <vm_name>
#
# Stop both the upgrade service AND its timer so neither a NOTIFY-driven
# nor a poll/timer-driven claim can race the next fabricate_scheduled_upgrade_row
# call.  Call this immediately BEFORE fabricate_scheduled_upgrade_row in every
# scenario that has a running upgrade service and a fabricate step.
#
# Why this matters: if the HEAD row already exists (e.g. from discover()),
# fabricate_scheduled_upgrade_row's ON CONFLICT DO UPDATE fires the
# upgrade_notify_daemon_trigger (AFTER UPDATE), which pg_notify's the
# running service.  The service calls executeScheduled → claims the row
# (started_at = now()) → QueryScheduledUpgrade returns nil (started_at IS NOT
# NULL filtered) → ./sb install sees StateNothingScheduled → step-table →
# completeInstallUpgradeRow.  The inject never fires.  Quiescing first
# eliminates the listener: the NOTIFY goes unheard, the row stays 'scheduled'
# for ./sb install or the restarted service to pick up with the inject in place.
#
# The timer (statbus-upgrade@statbus.timer) may be absent on some VMs;
# the || true makes the stop idempotent whether or not the unit exists.
# The service quiesce is SIGKILL-class (NOT a bare stop/SIGTERM — see the body
# comment): a SIGTERM fires the upgrade daemon's rollback handler. That is the
# critical gate.
#
# Recovery: the step-table's `systemctl --user enable --now <instance>`
# (install.go:1806) re-enables AND starts the service even from a fully
# stopped state, so quiescing pre-inject does NOT break the later recovery
# phase.
#
# INVARIANT — call quiesce_upgrade_service before EVERY
# fabricate_scheduled_upgrade_row EXCEPT the scenarios whose POINT is the
# service-DISPATCHED path (the running service must claim + dispatch the row):
#   - 0-happy-upgrade              (unattended service dispatch IS the test)
#   - 3-postswap-migration-timeout (service dispatches, then hits the
#                                    startup-timeout inject on its restart)
# Every other fabricate caller drives recovery via `./sb install` and carries
# a fabricate-claim race the running service would otherwise win — quiesce it.
# ─────────────────────────────────────────────────────────────────────────
quiesce_upgrade_service() {
    local vm_name="$1"
    echo "  [quiesce] SIGKILL-class quiescing upgrade timer + service on $vm_name (pre-fabricate race prevention)"
    # NEVER `systemctl --user stop <service>`: that sends SIGTERM, which the upgrade
    # daemon catches (signal.NotifyContext(ctx, …SIGTERM), service.go:1460) → cancels
    # the upgrade context → deferred rollback() fires (pg_restore + restoreGitState),
    # even on an idle / auto-discovered upgrade. That corrupted DB+git state and routed
    # the inject install to the step-table (db-unreachable) — the RUN-A 13/14 gate
    # failure. Mirror the product's SIGKILL-class quiesce (cli/cmd/install_upgrade.go:316
    # stopRestartUpgradeUnit): mask → SIGKILL → stop → reset-failed → unmask.
    #  - mask --runtime: a masked unit cannot start, so Restart=always (RestartSec=30)
    #    cannot respawn between the kill and the stop (race-free).
    #  - kill --signal=SIGKILL: whole-cgroup kill, NO handlers run → no rollback.
    #  - stop: nothing alive to signal → only cancels any pending auto-restart, lands inactive.
    #  - reset-failed: clears the SIGKILL (137) failure state + NRestarts counter.
    #  - unmask --runtime: clears the runtime-scoped mask set above (a PLAIN `unmask` does
    #    NOT clear a --runtime mask — the scopes must pair) so the unit is startable again:
    #    both the step-table's `systemctl --user enable --now` (install.go:1806) in recovery
    #    AND a scenario's direct `systemctl --user start` succeed. (unmask ≠ enable: the unit
    #    keeps its prior enabled state, nothing starts it until recovery/the scenario does.)
    VM_EXEC systemctl --user stop "statbus-upgrade@statbus.timer" 2>/dev/null || true
    VM_EXEC systemctl --user mask --runtime "statbus-upgrade@statbus.service" 2>/dev/null || true
    VM_EXEC systemctl --user kill --signal=SIGKILL "statbus-upgrade@statbus.service" 2>/dev/null || true
    VM_EXEC systemctl --user stop "statbus-upgrade@statbus.service" 2>/dev/null || true
    VM_EXEC systemctl --user reset-failed "statbus-upgrade@statbus.service" 2>/dev/null || true
    VM_EXEC systemctl --user unmask --runtime "statbus-upgrade@statbus.service" 2>/dev/null || true
    echo "  [quiesce] ✓ upgrade service SIGKILL-class quiesced (rollback handler NOT triggered; unit re-enableable)"
}
