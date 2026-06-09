#!/bin/bash
# HARNESS_SKIP_DEFAULT: known-RED reproducer (STATBUS-017) — excluded from the
#   default/full run.sh suite + broad phase runs; runs only when named specifically.
# Scenario: 3-postswap-migration-deterministic-error   ── KNOWN-RED (STATBUS-017) ──
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  DELIBERATE, DETERMINISTIC REPRODUCER OF A CONFIRMED PRODUCT BUG          ║
# ║  (STATBUS-017 — the rune wedge). EXPECTED TO FAIL (RED) UNTIL THE         ║
# ║  RECOVERY-CODE FIX LANDS. *NOT* PART OF THE GREEN SUITE.                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# WHAT IT PROVES (cell (e) of the migrate commit<->record boundary)
# ─────────────────────────────────────────────────────────────────
# The sibling 3-postswap-migrate-killed-after-commit covers cell (c): a VALID
# migration that re-runs into "relation already exists". THIS scenario covers
# cell (e): a migration in a crashed upgrade's delta that ERRORS on EVERY apply
# (a genuinely unapplyable migration — e.g. a bad DDL, a RAISE, a reference to a
# missing object). For such a migration, forward progress is IMPOSSIBLE, so the
# ONLY coherent recovery is RESTORE -> state=rolled_back.
#
# THE ACTUAL BUG (STATBUS-017): the schema-skew-guard `./sb migrate up` runs
# BEFORE recoverFromFlag on BOTH recovery entrypoints —
#   - service boot:  cli/internal/upgrade/service.go:1644  (then recoverFromFlag :1669)
#   - ./sb install:  cli/cmd/install_upgrade.go:198         (then RecoverFromFlag :205)
# It re-runs the pending erroring migration -> the migration errors again ->
# markTerminal("BOOT_MIGRATE_UP_FAILED") + return (service.go:1656). The restore
# is GATED BEHIND this failing migrate-up and is NEVER reached:
#   - service boots-loop (Restart=always -> StartLimit -> unit failed);
#   - ./sb install exits non-zero with the row still state=in_progress.
# Because the migration can NEVER apply, forward-recovery is hopeless and restore
# is the only escape — yet the wedge gates it. cell (e) is the sharpest case for
# "forward-then-restore must RESTORE on migrate-up failure."
#
# DETERMINISTIC FABRICATION (no kill-timing, no migration delta)
# ──────────────────────────────────────────────────────────────
#   1. a SYNTHETIC pending migration whose up.sql ALWAYS errors (RAISE EXCEPTION) —
#      far-future version so it is the SOLE pending migration;
#   2. a fabricated in_progress public.upgrade row + a service-held crash flag
#      (dead holder PID, Phase=resuming) so the INTENDED terminal is rolled_back.
# No object pre-creation is needed (unlike cell (c)) — the migration errors on
# its own. The ONLY reason this scenario goes RED is the wedge.
#
# RUN
# ───
#   ./test/install-recovery/scenarios/3-postswap-migration-deterministic-error.sh
#   (or: ./dev.sh test-install-recovery 3-postswap-migration-deterministic-error)
#
# Optional env:
#   KEEP_VM=1 / KEEP_VM_ON_FAILURE=1   Leave VM up for post-mortem
#   BOOTLOOP_WAIT_S=N                  Seconds to let the service boot-loop (default 90)
#
# TO GO GREEN (after the STATBUS-017 fix): the fix must route the schema-skew
# migrate-up FAILURE to the restore path (or run recoverFromFlag first). A real
# pre-upgrade-active snapshot must then be present for the restore to land
# state=rolled_back rather than state=failed — see "FUTURE: seed snapshot".

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-migration-deterministic-error}"
BOOTLOOP_WAIT_S="${BOOTLOOP_WAIT_S:-90}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

UPGRADE_UNIT="statbus-upgrade@statbus.service"
ERRMIG_VERSION="20991231235958"   # far future -> guaranteed the sole pending migration
ERRMIG_DESC="harness_deterministic_error"
ERRMIG_MARKER="harness deterministic migration error (STATBUS-017 cell e)"
ERRMIG_UP="${ERRMIG_VERSION}_${ERRMIG_DESC}.up.sql"
ERRMIG_DOWN="${ERRMIG_VERSION}_${ERRMIG_DESC}.down.sql"

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-migration-deterministic-error  (KNOWN-RED — STATBUS-017)"
echo "  Deterministic erroring-migration wedge reproducer (no kill-timing, no delta)"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
HEAD_SHORT="${HEAD_SHA:0:8}"
echo "  HEAD: $HEAD_SHA ($HEAD_SHORT)"

# ─────────────────────────────────────────────────────────────────────────
# Inline fabrication helpers (scenario-local — data-helpers.sh is a shared
# file owned by other agents).
# ─────────────────────────────────────────────────────────────────────────

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

# Place a synthetic migration whose up.sql ALWAYS errors (RAISE EXCEPTION).
_push_erroring_migration() {
    echo "── pushing synthetic erroring migration ($ERRMIG_UP) ──"
    local up down
    up=$(mktemp); down=$(mktemp)
    cat > "$up" <<SQL
-- HARNESS-ONLY synthetic migration — NOT a real schema change.
-- Errors deterministically on EVERY apply to fabricate cell (e) of STATBUS-017:
-- the schema-skew-guard \`./sb migrate up\` re-runs this pending migration during
-- recovery, it errors again, and the restore is gated behind the failure.
DO \$harness\$
BEGIN
  RAISE EXCEPTION '${ERRMIG_MARKER}';
END
\$harness\$;
SQL
    cat > "$down" <<SQL
-- up.sql never succeeds, so there is nothing to undo.
SELECT 1;
SQL
    scp -O "${SSH_OPTS[@]}" "$up"   root@"$VM_IP":/tmp/errmig.up.sql  >/dev/null
    scp -O "${SSH_OPTS[@]}" "$down" root@"$VM_IP":/tmp/errmig.down.sql >/dev/null
    rm -f "$up" "$down"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "
        install -o statbus -g statbus -m 0644 /tmp/errmig.up.sql   /home/statbus/statbus/migrations/${ERRMIG_UP}
        install -o statbus -g statbus -m 0644 /tmp/errmig.down.sql /home/statbus/statbus/migrations/${ERRMIG_DOWN}
        rm -f /tmp/errmig.up.sql /tmp/errmig.down.sql
    "
    echo "  ✓ erroring migration placed (version $ERRMIG_VERSION)"
}

# Fabricate the in_progress upgrade row (chk in_progress arm: scheduled_at NOT
# NULL, started_at NOT NULL, completed_at NULL, rolled_back_at NULL). Echoes the id.
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
    echo "$out" | grep -E '^[0-9]+$' | tail -1
}

# Fabricate the service-held crash flag. Dead holder PID + no live flock =>
# state-ladder probe 3 (crashed-upgrade); Phase=resuming mirrors the real
# in-resume kill. backup_path points at the canonical persistent snapshot dir.
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
  "invoked_by": "harness:deterministic-error-fabrication",
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

# Loud, human-readable dump of the OBSERVED wedge.
_dump_wedge_evidence() {
    local label="$1"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  WEDGE OBSERVED (STATBUS-017 cell e) — $label"
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  latest public.upgrade row:"
    local sql; sql=$(mktemp)
    cat > "$sql" <<SQL
SELECT 'state=' || state || ' started_at=' || COALESCE(started_at::text,'∅') ||
       ' rolled_back_at=' || COALESCE(rolled_back_at::text,'∅') ||
       ' error=' || COALESCE(left(error,160),'∅')
  FROM public.upgrade ORDER BY id DESC LIMIT 1;
SELECT 'db.migration max_version=' || COALESCE(MAX(version),0) FROM db.migration;
SQL
    _run_sql_file_in_vm "$sql" 2>/dev/null | sed 's/^/    /' || true
    rm -f "$sql"
    echo "  flag file:"
    VM_EXEC bash -c 'ls -la ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null && echo PRESENT || echo ABSENT' 2>/dev/null | sed 's/^/    /' || true
    echo "  upgrade-unit journal (BOOT_MIGRATE_UP_FAILED / the RAISE marker):"
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 40 2>/dev/null | grep -iE 'BOOT_MIGRATE_UP_FAILED|deterministic migration error|migrate up|refuses to enter' | tail -12" 2>/dev/null | sed 's/^/    /' || true
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
# Stage 1 — fabricate the erroring-migration RED state (deterministic)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 1 — fabricate the always-erroring pending migration state"
echo "════════════════════════════════════════════════════════════════"

_push_erroring_migration
ROW_ID=$(_fabricate_in_progress_row)
echo "  fabricated in_progress upgrade row id=$ROW_ID"
_fabricate_crash_flag "$ROW_ID"

echo "── verifying fabricated RED shape ──"
assert_upgrade_row_state "$VM_NAME" "in_progress"
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || {
    echo "✗ fabricated flag file missing" >&2; exit 1; }
echo "  ✓ RED confirmed: row in_progress, flag present, a pending migration that always errors"

# ─────────────────────────────────────────────────────────────────────────
# Stage 2 — TRIGGER A: ./sb install crashed-upgrade recovery (operator path)
#
# FUTURE: seed snapshot — when the STATBUS-017 fix lands, restore needs a real
# ~/statbus-backups/pre-upgrade-active snapshot present here to land
# state=rolled_back (else state=failed). Today the wedge fires at `./sb migrate
# up` BEFORE any restore, so no snapshot is needed to prove RED.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2 — TRIGGER A: ./sb install (crashed-upgrade -> migrate up wedge)"
echo "════════════════════════════════════════════════════════════════"

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
VM_EXEC bash -c "sleep $BOOTLOOP_WAIT_S"
NRESTARTS=$(VM_EXEC bash -c "systemctl --user show $UPGRADE_UNIT --property=NRestarts --value 2>/dev/null" | tr -d ' \r\n' || echo "?")
echo "  observed NRestarts=$NRESTARTS"
_dump_wedge_evidence "after service restart (boot-loop)"

# ─────────────────────────────────────────────────────────────────────────
# Stage 4 — INTENDED-GREEN assertions (these FAIL today — the RED IS the proof)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 4 — intended-green assertions (EXPECTED RED until STATBUS-017 fixed)"
echo "════════════════════════════════════════════════════════════════"
echo "  (If these PASS, the rune wedge is FIXED — update STATBUS-017 + this header.)"

# INTENDED: an unapplyable migration in a crashed upgrade -> restore -> rolled_back.
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
echo "PASS: 3-postswap-migration-deterministic-error (rune wedge FIXED)"
