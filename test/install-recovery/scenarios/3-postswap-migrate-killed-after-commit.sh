#!/bin/bash
# HARNESS_SKIP_DEFAULT: STATBUS-017 regression reproducer — excluded from the
#   default/full run.sh suite + broad phase runs (it provisions a real VM and
#   seeds a DB snapshot). The post-swap self-heal migration-completeness gate
#   (canary fix, STATBUS-067) has landed, so this is EXPECTED to reach
#   state=rolled_back. It is validated this round in a SEPARATE one-off run
#   (exact-name selector), NOT promoted into the comprehensive strict-green
#   gate: the rolled_back terminal still needs empirical confirmation, and a
#   short landing must not red the gate signal nor force a full comprehensive
#   re-run per canary iteration. Promote to a permanent default-suite guard in
#   a follow-up once the separate run is confirmed green.
# Scenario: 3-postswap-migrate-killed-after-commit   ── EXPECTED-GREEN (STATBUS-017 FIXED) ──
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  DETERMINISTIC REGRESSION REPRODUCER OF THE rune wedge (STATBUS-017).     ║
# ║  The recovery-code fix HAS LANDED (direction (a): on a half-applied       ║
# ║  migration the schema-skew guard DEFERS to the snapshot-restore path),    ║
# ║  so this scenario is now EXPECTED GREEN — it proves the after-commit cell ║
# ║  restores to state=rolled_back instead of boot-looping. A RED here means  ║
# ║  the STATBUS-017 fix has regressed.                                       ║
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
# THE BUG THIS GUARDS AGAINST (STATBUS-017 — NOW FIXED): a schema-skew-guard
# `./sb migrate up` runs BEFORE recoverFromFlag on BOTH recovery entrypoints —
#   - service boot:  cli/internal/upgrade/service.go:1644 (then recoverFromFlag :1669)
#   - ./sb install:  cli/cmd/install_upgrade.go:198        (then RecoverFromFlag :205)
# That guard re-runs the committed-unrecorded migration -> "relation already
# exists". BEFORE the fix it then markTerminal("BOOT_MIGRATE_UP_FAILED")+return
# (boot-loop / non-zero exit; the restore was gated behind the failing
# migrate-up and never reached).
# THE FIX (direction (a)): when boot-migrate-up FAILS AND a service-held
# in-progress flag is present, the guard logs and FALLS THROUGH to
# recoverFromFlag -> the Resuming one-shot latch (service.go:755) ->
# recoveryRollback -> snapshot restore -> state=rolled_back (the rune shape).
# Refuse (markTerminal+return) is kept for the no-flag / install-held case — a
# genuine stale-schema refusal with no recovery owner.
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
# HOW IT LANDS GREEN (post-fix): Stage 1 fabricates the after-commit RED state
# AND the three restore prerequisites the rolled_back terminal needs —
#   R1: pin the `pre-upgrade` git branch (restoreGitState's fallback restore
#       target; without it the rollback ABORTS to state=failed, service.go:4645);
#   R2: seed a real ~/statbus-backups/pre-upgrade-active DB snapshot (else
#       restoreDatabase no-ops, exec.go:698, and the rolled_back is hollow —
#       the DB is never actually restored);
#   R3: the synthetic migration is a TRACKED commit on top of pre-upgrade so
#       `git checkout -f pre-upgrade` removes it (an untracked file would
#       survive the restore and re-wedge the next boot).
# Then both triggers (Stage 2 ./sb install, Stage 3 service restart) converge:
# boot-migrate-up fails -> falls through (service-held flag) -> Resuming latch ->
# restore snapshot -> state=rolled_back, flag cleared, orphan + synthetic
# migration gone. Stage 2's ./sb install exits 75 (EX_TEMPFAIL — rolled back).

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
echo "  Scenario: 3-postswap-migrate-killed-after-commit  (EXPECTED-GREEN — STATBUS-017 FIXED)"
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

# Pin the `pre-upgrade` git branch at the current (old) HEAD. R1 (STATBUS-017):
# restoreGitState resolves its target by `git rev-parse <previousVersion>` (a
# git-describe string that does NOT resolve) and falls back to the `pre-upgrade`
# branch (service.go:4943). Real executeUpgrade pins it at service.go:3500; the
# fabricated crash never ran executeUpgrade, so the harness must pin it — else
# restoreGitState's fallback also misses and the rollback ABORTS to state=failed
# (service.go:4645) instead of rolled_back. MUST run BEFORE _push_synthetic_migration
# commits on top, so pre-upgrade points at the pre-migration commit.
_pin_pre_upgrade_branch() {
    echo "── pinning pre-upgrade git branch at current HEAD (R1: restoreGitState fallback target) ──"
    VM_EXEC bash -c 'cd ~/statbus && git branch -f pre-upgrade HEAD && echo "  pre-upgrade -> $(git rev-parse --short pre-upgrade)"' || {
        echo "✗ failed to pin pre-upgrade branch" >&2; exit 1; }
}

# Commit the synthetic migration pair as a TRACKED git commit on top of the
# pinned pre-upgrade commit. The up.sql does a hard CREATE TABLE (no IF NOT
# EXISTS) so a re-run against the pre-created object errors deterministically
# with "relation already exists".
#
# R3 (STATBUS-017): the migration MUST be git-TRACKED, not an untracked file.
# restoreGitState does `git checkout -f pre-upgrade`, which discards tracked
# changes but does NOT remove untracked files — an untracked synthetic migration
# would survive the restore and re-wedge the next boot. A migrations-ONLY commit
# keeps the rc.65 freshness/staleness guard silent: it diffs only cli/ between
# the binary's commit and HEAD (freshness/check.go:213), so a migrations-only
# delta shows no cli/ drift -> no self-heal `make build` (the VM has no Go).
_push_synthetic_migration() {
    echo "── committing synthetic pending migration ($SENTINEL_UP) as a TRACKED commit (R3) ──"
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
    # Copy into migrations/ as statbus (repo owner), then git add + commit. The
    # commit message has no single quotes, so a single-quoted bash -c body is
    # safe; SENTINEL_* are spliced locally via '"…"' (no special chars).
    # gpgsign=false + inline identity so no VM-side git config is required.
    VM_EXEC bash -c '
        set -e
        cd ~/statbus
        cp /tmp/sentinel.up.sql   migrations/'"$SENTINEL_UP"'
        cp /tmp/sentinel.down.sql migrations/'"$SENTINEL_DOWN"'
        rm -f /tmp/sentinel.up.sql /tmp/sentinel.down.sql
        git add migrations/'"$SENTINEL_UP"' migrations/'"$SENTINEL_DOWN"'
        git -c user.email=harness@statbus.test -c user.name=harness -c commit.gpgsign=false \
            commit -q -m "harness: synthetic after-commit migration (STATBUS-017 reproducer)"
        echo "  committed; HEAD -> $(git rev-parse --short HEAD), pre-upgrade -> $(git rev-parse --short pre-upgrade)"
    ' || { echo "✗ failed to commit synthetic migration" >&2; exit 1; }
    echo "  ✓ synthetic migration committed (version $SENTINEL_VERSION, tracked on top of pre-upgrade)"
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
    # Quiesce before fabricate (>&2 keeps this helper's captured row-id stdout
    # clean): closes the fabricate→in_progress-UPDATE window where the running
    # service could claim the scheduled row. Fabricate-claim invariant.
    quiesce_upgrade_service "$VM_NAME" >&2
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

# Loud, human-readable dump of the recovery state after each trigger — the
# narrative the King reads: guard fails -> defers -> Resuming latch -> restore ->
# rolled_back.
_dump_wedge_evidence() {
    local label="$1"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  RECOVERY EVIDENCE (STATBUS-017) — $label"
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
    echo "  upgrade-unit journal (guard-fail -> defer -> restore narrative):"
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 60 2>/dev/null | grep -iE 'BOOT_MIGRATE_UP_FAILED|relation already exists|deferring to recoverFromFlag|UPGRADE_DIED_DURING_RESUME|rolled back to the snapshot|Rollback complete|migrate up' | tail -14" 2>/dev/null | sed 's/^/    /' || true
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
}

# Faithfulness assert (2c): after recovery, the wedge object (orphan TABLE) must
# be GONE (the DB was actually restored, not a hollow no-op) AND the synthetic
# migration must be unrecorded in db.migration AND its file removed (the restore
# rolled back, it did not forward-complete). Guards against a hollow rolled_back
# slipping through if the snapshot seed (R2) silently breaks.
_assert_faithful_restore() {
    echo "── asserting faithful restore (orphan removed; synthetic migration unrecorded + file gone) ──"
    local sql; sql=$(mktemp)
    cat > "$sql" <<SQL
SELECT 'orphan_present=' || (to_regclass('${SENTINEL_TABLE}') IS NOT NULL)::text;
SELECT 'synthetic_recorded=' || EXISTS(SELECT 1 FROM db.migration WHERE version = ${SENTINEL_VERSION})::text;
SQL
    local out; out=$(_run_sql_file_in_vm "$sql"); rm -f "$sql"
    echo "$out" | sed 's/^/    /'
    if echo "$out" | grep -q 'orphan_present=true'; then
        echo "✗ faithfulness: orphan table still present after restore (DB not actually restored — hollow rolled_back)" >&2; exit 1; fi
    if echo "$out" | grep -q 'synthetic_recorded=true'; then
        echo "✗ faithfulness: synthetic migration recorded in db.migration (forward-completed, not restored)" >&2; exit 1; fi
    if VM_EXEC bash -c "test -f ~/statbus/migrations/${SENTINEL_UP}"; then
        echo "✗ faithfulness: synthetic migration file still on disk (git restore did not drop the tracked commit)" >&2; exit 1; fi
    echo "  ✓ faithful restore: orphan gone, synthetic migration unrecorded + file removed"
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

# Ordering is LOAD-BEARING (architect plan §2): pin pre-upgrade (R1) -> commit the
# synthetic migration on top (R3) -> fabricate the in_progress row -> seed the
# snapshot (R2) so it captures the row but NOT the orphan -> precreate the orphan
# (the wedge object) -> fabricate the resuming flag.
_pin_pre_upgrade_branch
_push_synthetic_migration
ROW_ID=$(_fabricate_in_progress_row)
echo "  fabricated in_progress upgrade row id=$ROW_ID"
seed_pre_upgrade_snapshot "$VM_NAME"
_precreate_committed_unrecorded_object
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
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2 — TRIGGER A: ./sb install (crashed-upgrade -> migrate up -> defer -> restore)"
echo "════════════════════════════════════════════════════════════════"

# `./sb install` with the flag present detects state-ladder probe 3
# (crashed-upgrade) -> runCrashRecovery -> `./sb migrate up` (install_upgrade.go:198)
# -> "relation already exists" -> the migrate up FAILS, but with a service-held
# in-progress flag present the STATBUS-017 fix FALLS THROUGH to RecoverFromFlag
# (:205) -> Resuming latch -> recoveryRollback -> restore snapshot -> rolled_back
# -> os.Exit(75) (EX_TEMPFAIL, service.go:4902). So `./sb install` EXITS 75 here
# (rolled back, not the old wedge's abort). Capture rather than let `set -e` abort.
RECOVER_RC=0
install_statbus_in_vm "$VM_NAME" || RECOVER_RC=$?
echo "  ./sb install (recovery) exit code: $RECOVER_RC  (EXPECTED 75 — rolled back via the restore path)"

_dump_wedge_evidence "after ./sb install crashed-upgrade"

# ─────────────────────────────────────────────────────────────────────────
# Stage 3 — TRIGGER B: service restart -> confirm a CLEAN boot (no re-wedge)
#
# Stage 2's ./sb install already rolled back: the flag is cleared, the synthetic
# migration file is gone (git restored to pre-upgrade), the orphan is gone, and
# the row is rolled_back. So the restarted unit boots clean — boot-migrate-up has
# nothing pending (synthetic file removed) -> succeeds -> recoverFromFlag (no
# flag) -> healthy. NRestarts must stay bounded (the post-fix contract); a
# boot-loop here would mean the restore left a re-wedging state (R3 regression).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 3 — TRIGGER B: service restart (confirm clean boot after recovery)"
echo "════════════════════════════════════════════════════════════════"
echo "── restarting $UPGRADE_UNIT and letting it settle for ${BOOTLOOP_WAIT_S}s ──"
VM_EXEC bash -c "systemctl --user reset-failed $UPGRADE_UNIT 2>/dev/null; systemctl --user restart $UPGRADE_UNIT 2>/dev/null || true"
VM_EXEC bash -c "sleep $BOOTLOOP_WAIT_S"
NRESTARTS=$(VM_EXEC bash -c "systemctl --user show $UPGRADE_UNIT --property=NRestarts --value 2>/dev/null" | tr -d ' \r\n' || echo "?")
echo "  observed NRestarts=$NRESTARTS  (EXPECTED low — no boot-loop after the fix)"
_dump_wedge_evidence "after service restart (clean boot expected)"

# ─────────────────────────────────────────────────────────────────────────
# Stage 4 — post-recovery assertions (EXPECTED GREEN — the STATBUS-017 fix)
#
# Each assertion states the post-fix contract. They run LAST so the recovery
# evidence above is already printed; the first failure exits non-zero.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 4 — post-recovery assertions (EXPECTED GREEN — STATBUS-017 fixed)"
echo "════════════════════════════════════════════════════════════════"
echo "  (A RED here means the STATBUS-017 fix regressed — do NOT relax; investigate.)"

# CONTRACT: recovery restored the snapshot and rolled the row back.
assert_upgrade_row_state "$VM_NAME" "rolled_back"
# CONTRACT: the Resuming one-shot latch's restore narrative landed. The flag's
# Phase=resuming routes recoverFromFlag to recoveryRollback via ErrResumeDied
# (service.go:755), NOT the dead forward-recovery branch — so the error reads
# "UPGRADE_DIED_DURING_RESUME: … rolled back to the snapshot. NO retry …".
assert_upgrade_row_error_matches "$VM_NAME" "UPGRADE_DIED_DURING_RESUME.*rolled back to the snapshot"
# CONTRACT: the mutex was released on a landed terminal write.
assert_flag_file_absent "$VM_NAME"
# CONTRACT: no boot-loop — the rune NRestarts pathology must not appear.
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 2
# CONTRACT: app healthy at the old version after rollback.
assert_health_passes "$VM_NAME"
# CONTRACT (faithfulness): the DB was actually restored (orphan gone) and the
# migration rolled back, not forward-completed (unrecorded + file removed).
_assert_faithful_restore

echo ""
echo "PASS: 3-postswap-migrate-killed-after-commit (rune wedge FIXED — restores to rolled_back)"
