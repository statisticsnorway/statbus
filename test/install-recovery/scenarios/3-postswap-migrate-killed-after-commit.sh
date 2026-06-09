#!/bin/bash
# HARNESS_SKIP_DEFAULT: known-RED reproducer (STATBUS-017) — excluded from the
#   default/full run.sh suite + broad phase runs; runs only when named specifically.
# Scenario: 3-postswap-migrate-killed-after-commit   ── KNOWN-RED (STATBUS-017) ──
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  THIS SCENARIO IS A DELIBERATE, DETERMINISTIC REPRODUCER OF A CONFIRMED   ║
# ║  PRODUCT BUG (STATBUS-017 — the rune wedge). IT IS EXPECTED TO FAIL (RED) ║
# ║  UNTIL THE RECOVERY-CODE FIX LANDS. IT IS *NOT* PART OF THE GREEN SUITE.  ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# WHAT IT PROVES
# ──────────────
# The "after-commit" cell of the migrate commit<->record boundary: a migration
# whose outer transaction has COMMITTED but whose db.migration ledger row was
# never written (the ~ms window a SIGKILL can land in during an upgrade's
# resume-migrate). The INTENDED recovery for this state is forward-fails-then-
# RESTORE: `./sb migrate up` re-lists the migration as pending, re-runs its
# CREATE, hits "relation already exists", and recovery RESTORES the snapshot ->
# state=rolled_back (the rune shape).
#
# THE ACTUAL BUG (STATBUS-017): a schema-skew-guard `./sb migrate up` runs
# BEFORE recoverFromFlag on BOTH recovery entrypoints —
#   - service boot:  cli/internal/upgrade/service.go:1644 (then recoverFromFlag :1669)
#   - ./sb install:  cli/cmd/install_upgrade.go:198        (then RecoverFromFlag :205)
# That guard re-runs the committed-unrecorded migration -> "relation already
# exists" -> markTerminal("BOOT_MIGRATE_UP_FAILED") + return (service.go:1656).
# The restore is GATED BEHIND this failing migrate-up and is NEVER reached:
#   - service boots-loop (Restart=always -> StartLimit -> unit failed);
#   - ./sb install exits non-zero with the row still state=in_progress.
# (The forward-recovery+restore branch at service.go:838-927 is itself dead code
#  for service-held flags — the PreSwap=="" guard at :822 intercepts first.)
#
# WHY THIS REWRITE EXISTS (vs the prior kill-timing version)
# ──────────────────────────────────────────────────────────
# The prior version reproduced the after-commit state by SIGKILL-timing a real
# resume-migrate (STATBUS_INJECT_AT=...after-commit-before-recorded) against a
# real v2026.05.2->HEAD migration delta. Both legs are fragile:
#   - the kill must land in a ~ms window (flaky); and
#   - it needs a real pending-migration delta, but the HEAD db-seed collapses
#     v2026.05.2->HEAD to zero pending migrations, so the stall site is often
#     never reached.
# This rewrite FABRICATES the exact after-commit RED state deterministically —
# no kill-timing, no migration delta — so the wedge reproduces every run:
#   1. a SYNTHETIC pending migration file (far-future version, sole pending);
#   2. its object pre-created out-of-band (committed) but its db.migration row
#      OMITTED  -> committed-but-unrecorded, exactly the after-commit shape;
#   3. a fabricated in_progress public.upgrade row + a service-held crash flag
#      (dead holder PID, Phase=resuming) so the INTENDED terminal is rolled_back.
# The ONLY reason this scenario goes RED is the wedge — there is no other
# moving part to blame.
#
# RUN
# ───
#   ./test/install-recovery/scenarios/3-postswap-migrate-killed-after-commit.sh
#   (or via the harness: ./dev.sh test-install-recovery 3-postswap-migrate-killed-after-commit)
#
# Optional env:
#   KEEP_VM=1 / KEEP_VM_ON_FAILURE=1   Leave VM up for post-mortem
#   BOOTLOOP_WAIT_S=N                  Seconds to let the service boot-loop (default 90)
#
# TO GO GREEN (after the STATBUS-017 fix lands): the fix must route the
# schema-skew migrate-up FAILURE to the restore path (or run recoverFromFlag
# first). At that point this scenario also needs a real pre-upgrade-active
# snapshot present for the restore to land state=rolled_back rather than
# state=failed — see "FUTURE: seed snapshot" near the trigger below.

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-migrate-killed-after-commit}"
BOOTLOOP_WAIT_S="${BOOTLOOP_WAIT_S:-90}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

UPGRADE_UNIT="statbus-upgrade@statbus.service"
SENTINEL_VERSION="20991231235959"   # far future -> guaranteed the sole pending migration
SENTINEL_DESC="harness_after_commit_sentinel"
SENTINEL_TABLE="public.harness_after_commit_sentinel"
SENTINEL_UP="${SENTINEL_VERSION}_${SENTINEL_DESC}.up.sql"
SENTINEL_DOWN="${SENTINEL_VERSION}_${SENTINEL_DESC}.down.sql"

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-migrate-killed-after-commit  (KNOWN-RED — STATBUS-017)"
echo "  Deterministic after-commit wedge reproducer (no kill-timing, no delta)"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
HEAD_SHORT="${HEAD_SHA:0:8}"
echo "  HEAD: $HEAD_SHA ($HEAD_SHORT)"

# ─────────────────────────────────────────────────────────────────────────
# Inline fabrication helpers (this scenario OWNS them — data-helpers.sh is a
# shared file owned by other agents; keeping the fabrication local avoids a
# cross-file collision and keeps the RED state's construction in one place).
# ─────────────────────────────────────────────────────────────────────────

# Run a SQL file against the VM's DB as the statbus user (CLAUDE.md: never echo
# SQL over SSH — write local, scp, pipe via redirect).
_run_sql_file_in_vm() {
    local local_sql="$1"
    # Pipe the SQL as ssh stdin straight into `./sb psql` as the statbus user
    # (CLAUDE.md's blessed `ssh host "…psql" < file` pattern; mirrors the
    # assertions' `<<<` usage). Do NOT scp to a /tmp file first: scp -O lands it
    # at mode 600 owned by root, which the statbus user cannot read — the
    # "/tmp/harness-sql.sql: Permission denied" fabrication bug (run 27177205304).
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" < "$local_sql"
}

# Place the synthetic migration pair into ~/statbus/migrations/ on the VM.
# The up.sql does a hard CREATE TABLE (no IF NOT EXISTS) so a re-run against an
# already-present object errors deterministically with "relation already exists".
_push_synthetic_migration() {
    echo "── pushing synthetic pending migration ($SENTINEL_UP) ──"
    local up down
    up=$(mktemp); down=$(mktemp)
    cat > "$up" <<SQL
-- HARNESS-ONLY synthetic migration — NOT a real schema change.
-- Fabricates the after-commit RED state for STATBUS-017: the object below is
-- pre-created out-of-band and this migration's db.migration row is OMITTED, so
-- \`./sb migrate up\` re-lists this version as pending and re-runs the CREATE ->
-- "relation already exists" -> the schema-skew-guard migrate-up wedge.
CREATE TABLE ${SENTINEL_TABLE} (id integer PRIMARY KEY);
SQL
    cat > "$down" <<SQL
DROP TABLE IF EXISTS ${SENTINEL_TABLE};
SQL
    scp -O "${SSH_OPTS[@]}" "$up"   root@"$VM_IP":/tmp/sentinel.up.sql  >/dev/null
    scp -O "${SSH_OPTS[@]}" "$down" root@"$VM_IP":/tmp/sentinel.down.sql >/dev/null
    rm -f "$up" "$down"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "
        install -o statbus -g statbus -m 0644 /tmp/sentinel.up.sql   /home/statbus/statbus/migrations/${SENTINEL_UP}
        install -o statbus -g statbus -m 0644 /tmp/sentinel.down.sql /home/statbus/statbus/migrations/${SENTINEL_DOWN}
        rm -f /tmp/sentinel.up.sql /tmp/sentinel.down.sql
    "
    echo "  ✓ synthetic migration placed (version $SENTINEL_VERSION)"
}

# Create the sentinel object out-of-band (committed) WITHOUT recording it in
# db.migration — the committed-but-unrecorded shape. This is the deterministic
# stand-in for "migration N committed, db.migration INSERT never ran".
_precreate_committed_unrecorded_object() {
    echo "── pre-creating committed-but-unrecorded object ($SENTINEL_TABLE) ──"
    local sql; sql=$(mktemp)
    cat > "$sql" <<SQL
CREATE TABLE ${SENTINEL_TABLE} (id integer PRIMARY KEY);
SELECT 'sentinel-created=' || (to_regclass('${SENTINEL_TABLE}') IS NOT NULL)::text;
SQL
    _run_sql_file_in_vm "$sql"
    rm -f "$sql"
    echo "  ✓ object committed; db.migration row deliberately omitted"
}

# Fabricate the in_progress upgrade row (chk_upgrade_state_attributes in_progress
# arm: scheduled_at NOT NULL, started_at NOT NULL, completed_at NULL,
# rolled_back_at NULL). Reuses fabricate_scheduled_upgrade_row for the row's
# existence + column shape, then transitions it to in_progress. Echoes the row id.
_fabricate_in_progress_row() {
    fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_SHA" >&2
    local sql; sql=$(mktemp)
    cat > "$sql" <<SQL
UPDATE public.upgrade
   SET state = 'in_progress'::public.upgrade_state,
       started_at = now(),
       completed_at = NULL,
       rolled_back_at = NULL
 WHERE commit_sha = '${HEAD_SHA}';
SELECT id FROM public.upgrade WHERE commit_sha = '${HEAD_SHA}';
SQL
    local out; out=$(_run_sql_file_in_vm "$sql"); rm -f "$sql"
    # The trailing SELECT prints the bare integer id; ignore any psql command
    # tags ("UPDATE 1") by matching the last pure-integer line.
    echo "$out" | grep -E '^[0-9]+$' | tail -1
}

# Fabricate the service-held crash flag (tmp/upgrade-in-progress.json). Dead
# holder PID + no live flock => state-ladder probe 3 (crashed-upgrade) fires;
# Phase=resuming mirrors the real after-commit kill (the kill lands inside
# applyPostSwap's migrate, after resumePostSwap stamped Resuming). backup_path
# points at the canonical persistent snapshot dir so a future fix's restore
# finds it if a snapshot is seeded (see FUTURE note at the trigger).
_fabricate_crash_flag() {
    local row_id="$1"
    echo "── fabricating service-held crash flag (Phase=resuming, dead PID) ──"
    local flag; flag=$(mktemp)
    cat > "$flag" <<JSON
{
  "id": ${row_id},
  "commit_sha": "${HEAD_SHA}",
  "commit_tags": [],
  "pid": 999999,
  "started_at": "2026-01-01T00:00:00Z",
  "invoked_by": "harness:after-commit-fabrication",
  "trigger": "scheduled",
  "holder": "service",
  "phase": "resuming",
  "recreate": false,
  "backup_path": "/home/statbus/statbus-backups/pre-upgrade-active"
}
JSON
    scp -O "${SSH_OPTS[@]}" "$flag" root@"$VM_IP":/tmp/upgrade-flag.json >/dev/null
    rm -f "$flag"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "
        install -o statbus -g statbus -m 0644 /tmp/upgrade-flag.json /home/statbus/statbus/tmp/upgrade-in-progress.json
        rm -f /tmp/upgrade-flag.json
    "
    echo "  ✓ crash flag written (id=$row_id)"
}

# Loud, human-readable dump of the OBSERVED wedge — printed even though the
# intended-green assertions below will then fail (RED). This is the proof block
# the King reads.
_dump_wedge_evidence() {
    local label="$1"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  WEDGE OBSERVED (STATBUS-017) — $label"
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  latest public.upgrade row:"
    local sql; sql=$(mktemp)
    cat > "$sql" <<SQL
SELECT 'state=' || state || ' started_at=' || COALESCE(started_at::text,'∅') ||
       ' rolled_back_at=' || COALESCE(rolled_back_at::text,'∅') ||
       ' error=' || COALESCE(left(error,160),'∅')
  FROM public.upgrade ORDER BY id DESC LIMIT 1;
SELECT 'db.migration max_version=' || COALESCE(MAX(version),0) FROM db.migration;
SELECT 'sentinel_object_present=' || (to_regclass('${SENTINEL_TABLE}') IS NOT NULL);
SQL
    _run_sql_file_in_vm "$sql" 2>/dev/null | sed 's/^/    /' || true
    rm -f "$sql"
    echo "  flag file:"
    VM_EXEC bash -c 'ls -la ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null && echo PRESENT || echo ABSENT' 2>/dev/null | sed 's/^/    /' || true
    echo "  upgrade-unit journal (BOOT_MIGRATE_UP_FAILED / relation already exists):"
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 40 2>/dev/null | grep -iE 'BOOT_MIGRATE_UP_FAILED|relation already exists|migrate up|refuses to enter' | tail -12" 2>/dev/null | sed 's/^/    /' || true
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────
# Stage 0 — bootstrap + install at HEAD
# ─────────────────────────────────────────────────────────────────────────
bootstrap_install_test_vm "$VM_NAME"

echo ""
echo "── initial install at HEAD ──"
install_statbus_in_vm "$VM_NAME"
assert_health_passes "$VM_NAME"

BASELINE_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' ')
echo "  baseline db.migration max_version = $BASELINE_MAX_VERSION"

# ─────────────────────────────────────────────────────────────────────────
# Stage 1 — fabricate the after-commit RED state (deterministic)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 1 — fabricate the committed-but-unrecorded migration state"
echo "════════════════════════════════════════════════════════════════"

# ── Stop the LIVE upgrade unit BEFORE fabricating ──────────────────────────
# Stage 0's install started statbus-upgrade@statbus.service, which holds an open
# `LISTEN upgrade_apply` (cli/internal/upgrade/service.go:1604). The fabrication
# below sets scheduled_at on the upgrade row (fabricate_scheduled_upgrade_row),
# firing the upgrade_notify_daemon trigger -> pg_notify('upgrade_apply','sha-…')
# (migration 20260414193000). A live service wakes on that NOTIFY, runs a REAL
# executeUpgrade, and `docker compose stop db` for its backup (service.go:3462),
# yanking the DB out from under the remaining fabrication SQL — observed as
# `service "db" is not running` in run 27184220745, where BOTH reproducers died
# here before ever reaching the wedge. Stopping the unit first (Restart=always
# does NOT revive an explicit `systemctl stop`) lets the fabrication build the
# crash state in peace. The unit is idle at this point (no scheduled row exists
# yet), so SIGTERM exits it cleanly without touching the DB. Stage 3 restarts
# the unit explicitly to drive the boot-migrate-up wedge. This mirrors the green
# sibling 3-postswap-watchdog-reconnect, which stops the unit before it
# manipulates upgrade state.
echo "── stopping the live upgrade unit so the scheduled-row NOTIFY can't hijack fabrication ──"
VM_EXEC systemctl --user stop "$UPGRADE_UNIT" 2>/dev/null || true
UNIT_STATE_AFTER_STOP=$(VM_EXEC systemctl --user is-active "$UPGRADE_UNIT" 2>/dev/null || true)
echo "  upgrade unit is-active after stop: ${UNIT_STATE_AFTER_STOP:-unknown} (expect 'inactive' — NOT 'active')"

_push_synthetic_migration
_precreate_committed_unrecorded_object
ROW_ID=$(_fabricate_in_progress_row)
echo "  fabricated in_progress upgrade row id=$ROW_ID"
_fabricate_crash_flag "$ROW_ID"

# Verify the RED shape before triggering recovery.
echo "── verifying fabricated RED shape ──"
assert_upgrade_row_state "$VM_NAME" "in_progress"
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || {
    echo "✗ fabricated flag file missing" >&2; exit 1; }
echo "  ✓ RED confirmed: row in_progress, flag present, migration committed-but-unrecorded"

# ─────────────────────────────────────────────────────────────────────────
# Stage 2 — TRIGGER A: ./sb install crashed-upgrade recovery (operator path)
#
# FUTURE: seed snapshot — when the STATBUS-017 fix lands, restore needs a real
# ~/statbus-backups/pre-upgrade-active snapshot present here for the recovery to
# land state=rolled_back (else it lands state=failed). Today the wedge fires at
# `./sb migrate up` BEFORE any restore, so no snapshot is needed to prove RED.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2 — TRIGGER A: ./sb install (crashed-upgrade -> migrate up wedge)"
echo "════════════════════════════════════════════════════════════════"

# `./sb install` with the flag present detects state-ladder probe 3
# (crashed-upgrade) -> runCrashRecovery -> `./sb migrate up` (install_upgrade.go:198)
# -> "relation already exists" -> return err (RecoverFromFlag at :205 NEVER reached).
# EXPECTED non-zero exit; capture rather than let `set -e` abort.
RECOVER_RC=0
install_statbus_in_vm "$VM_NAME" || RECOVER_RC=$?
echo "  ./sb install (recovery) exit code: $RECOVER_RC  (EXPECTED non-zero — the wedge aborts crash recovery)"

_dump_wedge_evidence "after ./sb install crashed-upgrade"

# ─────────────────────────────────────────────────────────────────────────
# Stage 3 — TRIGGER B: service restart -> boot-migrate-up boot-loop
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 3 — TRIGGER B: service restart (boot-migrate-up boot-loop)"
echo "════════════════════════════════════════════════════════════════"
echo "── restarting $UPGRADE_UNIT and letting it boot-loop for ${BOOTLOOP_WAIT_S}s ──"
VM_EXEC bash -c "systemctl --user reset-failed $UPGRADE_UNIT 2>/dev/null; systemctl --user restart $UPGRADE_UNIT 2>/dev/null || true"
# Let systemd cycle boot-migrate-up -> fail -> Restart=always until StartLimit.
VM_EXEC bash -c "sleep $BOOTLOOP_WAIT_S"
NRESTARTS=$(VM_EXEC bash -c "systemctl --user show $UPGRADE_UNIT --property=NRestarts --value 2>/dev/null" | tr -d ' \r\n' || echo "?")
echo "  observed NRestarts=$NRESTARTS"
_dump_wedge_evidence "after service restart (boot-loop)"

# ─────────────────────────────────────────────────────────────────────────
# Stage 4 — INTENDED-GREEN assertions (these FAIL today — the RED IS the proof)
#
# Each assertion below states the post-fix contract. They run LAST so the wedge
# evidence above is already printed; the first failure exits non-zero (RED).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 4 — intended-green assertions (EXPECTED RED until STATBUS-017 fixed)"
echo "════════════════════════════════════════════════════════════════"
echo "  (If these PASS, the rune wedge is FIXED — update STATBUS-017 + this header.)"

# INTENDED: recovery restored the snapshot and rolled the row back.
assert_upgrade_row_state "$VM_NAME" "rolled_back"
# INTENDED: the restore narrative landed (forward failed -> auto-restored).
assert_upgrade_row_error_matches "$VM_NAME" "forward failed: .*; auto-restored from"
# INTENDED: the mutex was released on a landed terminal write.
assert_flag_file_absent "$VM_NAME"
# INTENDED: no boot-loop — the rune NRestarts pathology must not appear.
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 2
# INTENDED: app healthy at the old version after rollback.
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 3-postswap-migrate-killed-after-commit (rune wedge FIXED)"
