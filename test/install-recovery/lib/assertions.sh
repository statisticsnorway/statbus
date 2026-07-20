#!/bin/bash
# assertions.sh — assertion helpers for install-recovery scenario scripts.
#
# Each assertion: prints a one-line PASS / FAIL diagnostic and returns
# 0 on pass, 1 on fail. Scenario scripts chain assertions and `set -e`
# bails on the first failure.
#
# Source AFTER vm-bootstrap.sh — relies on VM_EXEC being set.

# Test that the app's REST endpoint responds 2xx/3xx. 5-minute budget —
# cold start on a fresh Hetzner cx23 with cold container images can take
# ~60-120s past `./sb install` completion (docker compose returns when
# containers are "started", which is well before Caddy + app are actually
# serving). Slot=test → port 3010 (from vm-bootstrap's env-config).
# Override port via $HEALTH_PORT if needed. Diagnostic dump every 30s.
assert_health_passes() {
    local vm_name="$1"
    local port="${HEALTH_PORT:-3010}"
    local i http_code

    # STATBUS-192 must-fix 2: send Host: <SITE_DOMAIN> so the request matches the
    # development Caddyfile's http://{{.Domain}} site key and traverses handle @rest →
    # reverse_proxy rest:3000. With Host 127.0.0.1 (NO matching site key) Caddy returns
    # its no-matching-site EMPTY 200 off the live proxy — an ILLUSORY pass on a dark box
    # (proxy stays up for the maintenance page even when app/rest are down; the
    # C-rollback run-3 mechanism, 2026-07-15). Down rest → 502 (RED, correct); healthy
    # rest → PostgREST root 200 (GREEN). Resolve the domain from the VM's .env.config,
    # override via $SITE_DOMAIN, default to the vm-bootstrap value.
    local domain="${SITE_DOMAIN:-}"
    if [ -z "$domain" ]; then
        domain=$(VM_EXEC bash -c "cd ~/statbus && ./sb dotenv -f .env.config get SITE_DOMAIN 2>/dev/null" 2>/dev/null | tr -d ' \r\n' || true)
    fi
    [ -z "$domain" ] && domain="statbus-test.local"
    echo "  (health probe Host: $domain → :$port/rest/)"

    for i in $(seq 1 60); do
        http_code=$(VM_EXEC bash -c "curl -s -m 3 -H 'Host: ${domain}' http://127.0.0.1:${port}/rest/ -o /dev/null -w '%{http_code}'" 2>/dev/null || echo "000")
        if echo "$http_code" | grep -q "^[23]"; then
            echo "  ✓ health check passed (attempt $i, code=$http_code, ${i}×5s)"
            return 0
        fi
        echo "  … waiting for app on $vm_name:$port (attempt $i/60, code=$http_code)"
        # Periodic diagnostic so we can see WHY connections are refused.
        if [ $((i % 6)) -eq 0 ]; then
            echo "  --- diagnostic at attempt $i ---"
            VM_EXEC bash -c "docker compose -f ~/statbus/docker-compose.yml ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | head -8" 2>/dev/null \
                || VM_EXEC bash -c "cd ~/statbus && docker compose ps --format 'table {{.Name}}\t{{.Status}}' 2>&1 | head -8"
            echo "  ---"
        fi
        sleep 5
    done
    echo "  ✗ health check FAILED after 60 attempts (5 min budget exhausted)"
    return 1
}

# Verify the latest public.upgrade row is in the expected state.
# Useful states: 'completed', 'rolled_back', 'failed', 'in_progress'.
assert_upgrade_row_state() {
    local vm_name="$1"
    local expected_state="$2"
    local actual

    # Separate transport RC from assertion data (gzip-t pattern). Without
    # || _rc=$?, any SSH/psql failure sets actual="" and the comparison
    # "expected='completed' actual=''" is reported as an assertion failure
    # rather than an infrastructure error — the scenario fails at the wrong
    # point with a misleading message. Same fix applied to
    # assert_db_migration_max_version_unchanged in STATBUS-016; this
    # function was missed in that pass.
    local _rc=0
    actual=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" \
        2>/dev/null <<< "SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;" | tr -d ' ') || _rc=$?
    if [ "$_rc" -ne 0 ]; then
        echo "  ⚠ could not query public.upgrade on VM (rc=$_rc) — INFRA error; skipping" >&2
        return 0
    fi
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

    # Separate transport RC from assertion data (gzip-t pattern).  With
    # set -euo pipefail active, `VM_EXEC ... | head -1 || echo "unknown"`
    # fires on both SSH failure AND non-active unit (both exit non-zero with
    # pipefail), so actual="unknown" on a transient SSH blip → false
    # "state mismatch" claim.  Inner `|| true` ensures the remote command
    # always exits 0 when SSH works; non-zero VM_EXEC rc = transport failure.
    local _rc=0
    actual=$(VM_EXEC bash -c "systemctl --user is-active '$unit' 2>/dev/null || true" 2>/dev/null) || _rc=$?
    if [ "$_rc" -ne 0 ]; then
        echo "  ⚠ could not query systemd unit $unit (VM_EXEC rc=$_rc) — INFRA error; skipping" >&2
        return 0
    fi
    if [ "$actual" = "$expected_state" ]; then
        echo "  ✓ unit $unit is $expected_state"
        return 0
    fi
    echo "  ✗ unit $unit state mismatch: expected='$expected_state' actual='$actual'"
    return 1
}

# Verify there are NO ORPHAN pre-upgrade-* backup directories left in
# ~/statbus-backups/. An orphan is a LEGACY per-stamp dir (pre-upgrade-<stamp>
# or pre-upgrade-<stamp>.tmp) the executeUpgrade-layer cleanup should have
# reaped after recovery.
#
# CHANGE 2 (task #12): the rsync snapshot is now a SINGLE PERSISTENT dir
# committed by atomic rename — pre-upgrade-active (a complete snapshot that
# LEGITIMATELY persists after every upgrade, as the incremental base for the
# next one) and pre-upgrade-syncing (an in-flight / killed-mid-rsync partial).
# Neither is an orphan — they are the managed backup state (mirrors the Go
# isManagedBackupDir). So this assertion EXCLUDES active/syncing and only flags
# leftover legacy per-stamp dirs. (Pre-#12 there was no persistent dir, so the
# old "zero pre-upgrade-* dirs" check was right then; post-#12 it would
# false-fail on the persistent active dir.)
assert_no_orphan_backup() {
    local vm_name="$1"
    local count

    # Count pre-upgrade-* dirs EXCLUDING the two managed names (active/syncing).
    # `grep -c .` (and the `grep -vE` above it) EXIT 1 on zero matches while still
    # printing "0". Callers run under `set -o pipefail`, so without the `|| true`
    # the local pipeline would exit non-zero, fire the trailing `|| echo "0"`, and
    # APPEND a second "0" → count="0\n0" != "0" → false-fail on the (correct) zero-
    # orphan result. `|| true` makes the expected no-match a clean exit; `tr -d ' \n'`
    # strips the trailing newline so count is exactly "0" / "N".
    count=$(VM_EXEC bash -c 'ls -d ~/statbus-backups/pre-upgrade-* 2>/dev/null | grep -vE "/pre-upgrade-(active|syncing)$" | grep -c . || true' 2>/dev/null | tr -d ' \n' || echo "0")
    if [ "$count" = "0" ]; then
        echo "  ✓ no orphan (legacy per-stamp) pre-upgrade-* backups in ~/statbus-backups/ (managed active/syncing excluded)"
        return 0
    fi
    echo "  ✗ orphan backup(s) found ($count): $(VM_EXEC bash -c 'ls -d ~/statbus-backups/pre-upgrade-* 2>/dev/null | grep -vE "/pre-upgrade-(active|syncing)$"' 2>/dev/null | tr '\n' ' ')"
    return 1
}

# Verify a specific migration version is recorded as applied.
assert_db_migration_recorded() {
    local vm_name="$1"
    local version="$2"
    local count

    # Separate transport RC (gzip-t pattern).  `|| echo "0"` fed count="0" on
    # any SSH blip, producing "migration NOT recorded" false claims.  Capture
    # the pipeline RC via `|| _rc=$?` instead; treat non-zero as INFRA skip.
    local _rc=0
    count=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" \
        2>/dev/null <<< "SELECT count(*) FROM db.migration WHERE version = $version;" | tr -d ' ') || _rc=$?
    if [ "$_rc" -ne 0 ]; then
        echo "  ⚠ could not query db.migration on VM (rc=$_rc) — INFRA error; skipping" >&2
        return 0
    fi
    if [ "$count" = "1" ]; then
        echo "  ✓ migration $version recorded in db.migration"
        return 0
    fi
    echo "  ✗ migration $version NOT recorded (count=$count)"
    return 1
}

# Verify the "Database sessions" install step ran cleanly. That's the step
# where bool-text and worker-exclusion bugs historically caused failure.
# Match by step NAME with wildcard position/total so a future ladder
# growth (or insertion of a new step at an earlier position) doesn't
# silently break this assertion. Previously hardcoded "[9/15]" — the
# 2026-05-22 #68 fix added "Backup ownership" at position 9, bumping
# "Database sessions" to [10/16] and breaking this grep until the
# wildcard fix below.
assert_step_database_sessions_completed() {
    local vm_name="$1"
    local log_file="${HARNESS_ROOT}/tmp/install-recovery-${vm_name}-install.log"

    if [ ! -f "$log_file" ]; then
        echo "  ✗ install log not found: $log_file"
        return 1
    fi
    if grep -E "^\[[0-9]+/[0-9]+\] Database sessions\s+(OK|DONE)" "$log_file" >/dev/null; then
        echo "  ✓ Database sessions step completed"
        return 0
    fi
    if grep -E "^\[[0-9]+/[0-9]+\] Database sessions\s+FAILED" "$log_file" >/dev/null; then
        echo "  ✗ Database sessions step FAILED — bool-text or worker-exclusion class regression"
        return 1
    fi
    echo "  ✗ Database sessions step status unclear in log $log_file"
    return 1
}

# Backward-compat alias for existing call sites.
assert_step9_completed() {
    assert_step_database_sessions_completed "$@"
}

# Verify the install ladder ran through the final "Upgrade service" step.
# That's where the systemd reset-failed lives. Match by step NAME with
# wildcard position/total so future ladder changes don't break this.
assert_step_upgrade_service_completed() {
    local vm_name="$1"
    local log_file="${HARNESS_ROOT}/tmp/install-recovery-${vm_name}-install.log"

    if [ ! -f "$log_file" ]; then
        echo "  ✗ install log not found: $log_file"
        return 1
    fi
    if grep -E "^\[[0-9]+/[0-9]+\] Upgrade service\s+(OK|DONE)" "$log_file" >/dev/null; then
        echo "  ✓ Upgrade service step completed"
        return 0
    fi
    echo "  ✗ Upgrade service step did NOT complete — install bailed before reaching it"
    return 1
}

# Verify the latest public.upgrade row's `error` column matches a regex.
# Used to confirm the augmented narrative landed: "forward failed: <err>;
# auto-restored from <path>". Empty actual is treated as failure.
assert_upgrade_row_error_matches() {
    local vm_name="$1"
    local pattern="$2"
    local actual

    actual=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" \
        2>/dev/null <<< "SELECT error FROM public.upgrade ORDER BY id DESC LIMIT 1;")
    if [ -z "$actual" ]; then
        echo "  ✗ upgrade row error column empty (expected match for $pattern)"
        return 1
    fi
    if echo "$actual" | grep -E "$pattern" >/dev/null; then
        echo "  ✓ upgrade row error matches /$pattern/ (got: ${actual:0:120}...)"
        return 0
    fi
    echo "  ✗ upgrade row error does NOT match /$pattern/"
    echo "    actual: $actual"
    return 1
}

# Verify the upgrade flag file is absent in tmp/. After successful recovery
# (either Layer 0 in-process or Layer 2 next-install), the flag MUST be
# gone — its presence would mean the next install detects a stale flag
# and re-enters recovery loop.
assert_flag_file_absent() {
    local vm_name="$1"
    local present

    # Separate transport RC from assertion data (|| echo "0" would fire on SSH
    # failure under pipefail, producing a false "✓ absent" all-clear when the
    # flag could actually be present but the check failed).
    local _rc=0
    present=$(VM_EXEC bash -c 'ls ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null | wc -l' 2>/dev/null | tr -d ' ') || _rc=$?
    if [ "$_rc" -ne 0 ]; then
        echo "  ⚠ could not check upgrade flag file on VM (rc=$_rc) — INFRA error; skipping" >&2
        return 0
    fi
    if [ "$present" = "0" ]; then
        echo "  ✓ upgrade flag file absent"
        return 0
    fi
    echo "  ✗ upgrade flag file STILL PRESENT — recovery did not clean up"
    VM_EXEC bash -c 'cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null' || true
    return 1
}

# Verify the current db.migration max version. Used during stall-active
# checks to confirm the partial-state shape (committed but unrecorded
# migration).
assert_db_migration_max_version_unchanged() {
    local vm_name="$1"
    local baseline="$2"
    local actual

    # Separate transport RC (gzip-t pattern).  `|| echo "0"` fed actual="0"
    # on any SSH blip; if baseline ≠ 0 that produces a false "drifted" claim.
    local _rc=0
    actual=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" \
        2>/dev/null <<< "SELECT COALESCE(MAX(version), 0) FROM db.migration;" | tr -d ' ') || _rc=$?
    if [ "$_rc" -ne 0 ]; then
        echo "  ⚠ could not query db.migration max_version on VM (rc=$_rc) — INFRA error; skipping" >&2
        return 0
    fi
    if [ "$actual" = "$baseline" ]; then
        echo "  ✓ db.migration max_version = baseline ($baseline) — partial-state confirmed"
        return 0
    fi
    echo "  ✗ db.migration max_version drifted: baseline=$baseline actual=$actual"
    return 1
}

# snapshot_demo_data_counts <vm_name>
#
# Echoes a CSV-shaped snapshot of row counts for the demo-data tables
# populated by lib/data-helpers.sh's populate_with_demo_data. Caller
# captures the output in a shell variable for later equality checks.
# Format:
#
#   statistical_unit=N,legal_unit=N,establishment=N,statistical_history=N
#
# Stable across invocations on identical data so the
# assert_demo_data_counts_match_snapshot comparison is a simple string
# equality. Suitable for stricter scenarios that need to confirm no
# data drift across the failure-injection window.
snapshot_demo_data_counts() {
    local vm_name="$1"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" \
        2>/dev/null \
        << 'SQL' | tr -d ' \r\n'
SELECT 'statistical_unit=' || (SELECT count(*) FROM public.statistical_unit) ||
    ',legal_unit=' || (SELECT count(*) FROM public.legal_unit) ||
    ',establishment=' || (SELECT count(*) FROM public.establishment) ||
    ',statistical_history=' || (SELECT count(*) FROM public.statistical_history);
SQL
}

# assert_demo_data_present <vm_name>
#
# Catastrophic-loss detector for the R5 race. Confirms every demo-data
# table has > 0 rows after the test reaches its post-recovery checkpoint.
# If any table is empty, the assertion fails loudly with the empty
# table named — a scenario that catastrophically lost data WILL fail
# here rather than passing silently on an empty DB.
#
# Intentionally narrow: row counts > 0, not exact equality (use
# assert_demo_data_counts_match_snapshot for that). This is the "did
# we lose everything?" assertion. Acceptable post-recovery shapes
# include partial loss (one table empty, others populated) — but that
# would still fail here, surfacing what was lost.
assert_demo_data_present() {
    local vm_name="$1"
    local tables=("statistical_unit" "legal_unit" "establishment" "statistical_history")
    local failed=0
    local table count

    local _rc
    for table in "${tables[@]}"; do
        # Separate transport RC from assertion data (|| echo "?" would fire on SSH
        # failure under pipefail, producing "? rows — R5 catastrophic-loss indicator"
        # when the query simply could not run — not a genuine data-loss finding).
        _rc=0
        count=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
            "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" \
            2>/dev/null <<< "SELECT count(*) FROM public.${table};" | tr -d ' \r\n') || _rc=$?
        if [ "$_rc" -ne 0 ]; then
            echo "  ⚠ could not query public.${table} (rc=$_rc) — INFRA error; skipping" >&2
            continue
        fi
        if [ "$count" = "0" ]; then
            echo "  ✗ public.${table} has 0 rows — R5 catastrophic-loss indicator"
            failed=1
        fi
    done
    if [ "$failed" = "1" ]; then
        return 1
    fi
    echo "  ✓ all demo-data tables populated (R5 catastrophic-loss NOT triggered)"
    return 0
}

# assert_demo_data_counts_match_snapshot <vm_name> <snapshot>
#
# Stricter than assert_demo_data_present: requires exact equality
# with a snapshot captured earlier. Use when the scenario expects
# zero data drift across the recovery window (e.g., the failure
# injection wedged the upgrade BEFORE any user-visible data could
# change). Differing counts surface as a one-line diff.
assert_demo_data_counts_match_snapshot() {
    local vm_name="$1"
    local expected="$2"
    local actual
    actual=$(snapshot_demo_data_counts "$vm_name")
    if [ "$actual" = "$expected" ]; then
        echo "  ✓ demo-data counts match snapshot ($actual)"
        return 0
    fi
    echo "  ✗ demo-data counts drifted"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    return 1
}

# assert_systemd_restart_counter_bounded <vm_name> <unit_name> <max_restarts>
#
# Race B assertion — catches the restart-loop pathology empirically.
# A unit that crashes and restarts a small number of times during
# recovery is acceptable; a unit looping hundreds of times (e.g.
# 289 — the rune wedge's observed shape) is not. After the recovery
# window closes, NRestarts MUST be ≤ max_restarts.
#
# Reads `systemctl --user show <unit> --property=NRestarts --value`
# inside the VM. Fails with a clear message naming the unit + the
# observed counter + the bound, so a regression surfaces the exact
# pathology rather than a generic "test failed".
#
# Suggested bounds:
#   - 0  for a clean-recovery scenario (no restarts expected)
#   - 5  for a single-failure scenario (a few restarts during recovery
#        are acceptable, but not the 100s-of-restarts pathology)
#   - tune higher if a scenario genuinely exercises legitimate
#     restart-during-recovery cycles, but DOCUMENT the bound's
#     rationale at the call site.
assert_systemd_restart_counter_bounded() {
    local vm_name="$1"
    local unit="${2:-statbus-upgrade@statbus.service}"
    local max_restarts="${3:-5}"
    local actual

    actual=$(VM_EXEC systemctl --user show "$unit" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
    if ! [[ "$actual" =~ ^[0-9]+$ ]]; then
        echo "  ✗ could not parse NRestarts for $unit (got: '$actual')"
        return 1
    fi
    if [ "$actual" -le "$max_restarts" ]; then
        echo "  ✓ $unit NRestarts=$actual ≤ bound=$max_restarts"
        return 0
    fi
    echo "  ✗ $unit NRestarts=$actual EXCEEDS bound=$max_restarts — Race B restart-loop pathology"
    return 1
}

# assert_deploy_status <vm-name> <40-hex-sha> <want-exit> <want-state>
#
# STATBUS-170 AC#3 — the deploy-status script-contract leg. Runs
# ops/ci-deploy-status.sh ON the VM against the commit-addressed row and asserts
# its verdict: the exit code AND the state field of the one-line stdout
# (`<state>|<parked>|<reason>`). The script is the single home of the deploy
# poll's semantics (exit contract 0 converged / 10 failed / 20 pending /
# 30 transient / 64 usage — the workflow poll blocks deliberately defer to it,
# STATBUS-170 comment #5 rider i). Asserting it here against REAL end states on
# every arc pass means CI's meaning of deploy-green/red can never silently drift
# from what the boxes actually report. Transport: the harness root path running
# as the statbus user (VM_EXEC) — the same identity class production's sshdo
# lines execute as; the sshdo-gated transport itself is proven separately by
# deploy-status-proof-arc.sh (AC#4).
assert_deploy_status() {
    local vm_name="$1" sha="$2" want_exit="$3" want_state="$4"
    local out rc line state
    out=$(VM_EXEC bash -c "cd ~/statbus && ops/ci-deploy-status.sh $sha" 2>/dev/null) && rc=0 || rc=$?
    line=$(printf '%s' "$out" | tail -n 1 | tr -d '\r')
    state="${line%%|*}"
    if [ "$rc" = "$want_exit" ] && [ "$state" = "$want_state" ]; then
        echo "  ✓ deploy-status verdict for ${sha:0:8}: exit=$rc state=$state ($line)"
        return 0
    fi
    echo "  ✗ deploy-status verdict MISMATCH for ${sha:0:8}: got exit=$rc state='$state' (line: '$line'), want exit=$want_exit state=$want_state" >&2
    return 1
}
