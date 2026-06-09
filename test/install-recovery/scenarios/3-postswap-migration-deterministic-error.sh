#!/bin/bash
# HARNESS_SKIP_DEFAULT: STATBUS-017 regression reproducer — excluded from the
#   default/full run.sh suite + broad phase runs (it provisions a real VM and
#   seeds a DB snapshot); runs only when named specifically.
# Scenario: 3-postswap-migration-deterministic-error   ── EXPECTED-GREEN (STATBUS-017 FIXED) ──
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  DETERMINISTIC REGRESSION REPRODUCER OF THE rune wedge (STATBUS-017),     ║
# ║  cell (e): a migration that errors on EVERY apply. The recovery-code fix  ║
# ║  HAS LANDED (direction (a): the schema-skew guard defers to the           ║
# ║  snapshot-restore path), so this is now EXPECTED GREEN — it proves an     ║
# ║  unapplyable migration restores to state=rolled_back instead of           ║
# ║  boot-looping. A RED here means the STATBUS-017 fix has regressed.        ║
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
# THE BUG THIS GUARDS AGAINST (STATBUS-017 — NOW FIXED): the schema-skew-guard
# `./sb migrate up` runs BEFORE recoverFromFlag on BOTH recovery entrypoints —
#   - service boot:  cli/internal/upgrade/service.go:1644  (then recoverFromFlag :1669)
#   - ./sb install:  cli/cmd/install_upgrade.go:198         (then RecoverFromFlag :205)
# It re-runs the pending erroring migration -> the migration errors again. BEFORE
# the fix it then markTerminal("BOOT_MIGRATE_UP_FAILED")+return (boot-loop /
# non-zero exit; the restore was gated behind the failing migrate-up and never
# reached). Because the migration can NEVER apply, forward-recovery is hopeless
# and restore is the ONLY escape — cell (e) is the sharpest case for the fix.
# THE FIX (direction (a)): when boot-migrate-up FAILS AND a service-held
# in-progress flag is present, the guard FALLS THROUGH to recoverFromFlag ->
# Resuming one-shot latch (service.go:755) -> recoveryRollback -> snapshot
# restore -> state=rolled_back. Refuse is kept for the no-flag / install-held case.
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
# HOW IT LANDS GREEN (post-fix): Stage 1 fabricates the erroring-migration RED
# state AND the restore prerequisites the rolled_back terminal needs —
#   R1: pin the `pre-upgrade` git branch (restoreGitState's fallback restore
#       target; without it the rollback ABORTS to state=failed, service.go:4645);
#   R2: seed a real ~/statbus-backups/pre-upgrade-active DB snapshot (else
#       restoreDatabase no-ops, exec.go:698, and the rolled_back is hollow);
#   R3: the erroring migration is a TRACKED commit on top of pre-upgrade so
#       `git checkout -f pre-upgrade` removes it — CRITICAL for cell (e): an
#       untracked erroring file would survive the restore and re-wedge the next
#       boot (re-run -> error -> no flag -> markTerminal -> boot-loop).
# Then both triggers converge: boot-migrate-up errors -> falls through ->
# Resuming latch -> restore snapshot -> state=rolled_back, flag cleared, erroring
# migration gone. Stage 2's ./sb install exits 75 (EX_TEMPFAIL — rolled back).

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
echo "  Scenario: 3-postswap-migration-deterministic-error  (EXPECTED-GREEN — STATBUS-017 FIXED)"
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

# Pin the `pre-upgrade` git branch at the current (old) HEAD. R1 (STATBUS-017):
# restoreGitState resolves its target by `git rev-parse <previousVersion>` (a
# git-describe string that does NOT resolve) and falls back to the `pre-upgrade`
# branch (service.go:4943). Real executeUpgrade pins it at service.go:3500; the
# fabricated crash never ran executeUpgrade, so the harness must pin it — else
# restoreGitState's fallback also misses and the rollback ABORTS to state=failed
# (service.go:4645). MUST run BEFORE _push_erroring_migration commits on top.
_pin_pre_upgrade_branch() {
    echo "── pinning pre-upgrade git branch at current HEAD (R1: restoreGitState fallback target) ──"
    VM_EXEC bash -c 'cd ~/statbus && git branch -f pre-upgrade HEAD && echo "  pre-upgrade -> $(git rev-parse --short pre-upgrade)"' || {
        echo "✗ failed to pin pre-upgrade branch" >&2; exit 1; }
}

# Commit a synthetic migration whose up.sql ALWAYS errors (RAISE EXCEPTION) as a
# TRACKED git commit on top of the pinned pre-upgrade commit.
#
# R3 (STATBUS-017) — CRITICAL for cell (e): the erroring migration MUST be
# git-TRACKED. restoreGitState does `git checkout -f pre-upgrade`, which discards
# tracked changes but does NOT remove untracked files. An untracked erroring
# migration would survive the restore and re-wedge the next boot (re-run ->
# errors -> no flag -> markTerminal -> boot-loop). A migrations-ONLY commit keeps
# the rc.65 freshness guard silent (it diffs only cli/, freshness/check.go:213).
_push_erroring_migration() {
    echo "── committing synthetic erroring migration ($ERRMIG_UP) as a TRACKED commit (R3) ──"
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
    # Copy into migrations/ as statbus (repo owner), then git add + commit. The
    # commit message has no single quotes, so a single-quoted bash -c body is
    # safe; ERRMIG_* are spliced locally via '"…"' (no special chars).
    # gpgsign=false + inline identity so no VM-side git config is required.
    VM_EXEC bash -c '
        set -e
        cd ~/statbus
        cp /tmp/errmig.up.sql   migrations/'"$ERRMIG_UP"'
        cp /tmp/errmig.down.sql migrations/'"$ERRMIG_DOWN"'
        rm -f /tmp/errmig.up.sql /tmp/errmig.down.sql
        git add migrations/'"$ERRMIG_UP"' migrations/'"$ERRMIG_DOWN"'
        git -c user.email=harness@statbus.test -c user.name=harness -c commit.gpgsign=false \
            commit -q -m "harness: synthetic deterministic-error migration (STATBUS-017 reproducer)"
        echo "  committed; HEAD -> $(git rev-parse --short HEAD), pre-upgrade -> $(git rev-parse --short pre-upgrade)"
    ' || { echo "✗ failed to commit erroring migration" >&2; exit 1; }
    echo "  ✓ erroring migration committed (version $ERRMIG_VERSION, tracked on top of pre-upgrade)"
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

# Loud, human-readable dump of the recovery state after each trigger.
_dump_wedge_evidence() {
    local label="$1"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  RECOVERY EVIDENCE (STATBUS-017 cell e) — $label"
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
    echo "  upgrade-unit journal (guard-fail -> defer -> restore narrative):"
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 60 2>/dev/null | grep -iE 'BOOT_MIGRATE_UP_FAILED|deterministic migration error|deferring to recoverFromFlag|UPGRADE_DIED_DURING_RESUME|rolled back to the snapshot|Rollback complete|migrate up' | tail -14" 2>/dev/null | sed 's/^/    /' || true
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
}

# Faithfulness assert (2c): after recovery, the erroring migration must be
# unrecorded in db.migration (it never applied) AND its file removed (the restore
# rolled the git tree back to pre-upgrade, dropping the tracked commit). Guards
# against a hollow rolled_back if the snapshot/git restore silently broke. (No
# orphan object in cell (e) — the migration errors on its own.)
_assert_faithful_restore() {
    echo "── asserting faithful restore (erroring migration unrecorded + file gone) ──"
    local sql; sql=$(mktemp)
    cat > "$sql" <<SQL
SELECT 'errmig_recorded=' || EXISTS(SELECT 1 FROM db.migration WHERE version = ${ERRMIG_VERSION})::text;
SQL
    local out; out=$(_run_sql_file_in_vm "$sql"); rm -f "$sql"
    echo "$out" | sed 's/^/    /'
    if echo "$out" | grep -q 'errmig_recorded=true'; then
        echo "✗ faithfulness: erroring migration recorded in db.migration (it should NEVER apply)" >&2; exit 1; fi
    if VM_EXEC bash -c "test -f ~/statbus/migrations/${ERRMIG_UP}"; then
        echo "✗ faithfulness: erroring migration file still on disk (git restore did not drop the tracked commit — re-wedge risk)" >&2; exit 1; fi
    echo "  ✓ faithful restore: erroring migration unrecorded + file removed"
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
# erroring migration on top (R3) -> fabricate the in_progress row -> seed the
# snapshot (R2) so it captures the row -> fabricate the resuming flag. No orphan
# object in cell (e) — the migration errors on its own apply.
_pin_pre_upgrade_branch
_push_erroring_migration
ROW_ID=$(_fabricate_in_progress_row)
echo "  fabricated in_progress upgrade row id=$ROW_ID"
seed_pre_upgrade_snapshot "$VM_NAME"
_fabricate_crash_flag "$ROW_ID"

echo "── verifying fabricated RED shape ──"
assert_upgrade_row_state "$VM_NAME" "in_progress"
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || {
    echo "✗ fabricated flag file missing" >&2; exit 1; }
echo "  ✓ RED confirmed: row in_progress, flag present, a pending migration that always errors"

# ─────────────────────────────────────────────────────────────────────────
# Stage 2 — TRIGGER A: ./sb install crashed-upgrade recovery (operator path)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2 — TRIGGER A: ./sb install (crashed-upgrade -> migrate up -> defer -> restore)"
echo "════════════════════════════════════════════════════════════════"

# `./sb install` detects crashed-upgrade -> runCrashRecovery -> `./sb migrate up`
# (install_upgrade.go:198) -> the erroring migration RAISEs -> migrate up FAILS,
# but with a service-held in-progress flag present the STATBUS-017 fix FALLS
# THROUGH to RecoverFromFlag (:205) -> Resuming latch -> recoveryRollback ->
# restore snapshot -> rolled_back -> os.Exit(75) (service.go:4902). So `./sb
# install` EXITS 75 here. Capture rather than let `set -e` abort.
RECOVER_RC=0
install_statbus_in_vm "$VM_NAME" || RECOVER_RC=$?
echo "  ./sb install (recovery) exit code: $RECOVER_RC  (EXPECTED 75 — rolled back via the restore path)"

_dump_wedge_evidence "after ./sb install crashed-upgrade"

# ─────────────────────────────────────────────────────────────────────────
# Stage 3 — TRIGGER B: service restart -> confirm a CLEAN boot (no re-wedge)
#
# Stage 2's ./sb install already rolled back: the flag is cleared, the erroring
# migration file is gone (git restored to pre-upgrade), and the row is
# rolled_back. So the restarted unit boots clean — boot-migrate-up has nothing
# pending (erroring file removed) -> succeeds -> recoverFromFlag (no flag) ->
# healthy. NRestarts must stay bounded; a boot-loop here would mean the restore
# left the erroring migration in place (R3 regression — the cell-(e) re-wedge).
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
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 4 — post-recovery assertions (EXPECTED GREEN — STATBUS-017 fixed)"
echo "════════════════════════════════════════════════════════════════"
echo "  (A RED here means the STATBUS-017 fix regressed — do NOT relax; investigate.)"

# CONTRACT: an unapplyable migration in a crashed upgrade -> restore -> rolled_back.
assert_upgrade_row_state "$VM_NAME" "rolled_back"
# CONTRACT: the Resuming one-shot latch's restore narrative landed (Phase=resuming
# routes to recoveryRollback via ErrResumeDied, service.go:755), NOT the dead
# forward-recovery branch.
assert_upgrade_row_error_matches "$VM_NAME" "UPGRADE_DIED_DURING_RESUME.*rolled back to the snapshot"
# CONTRACT: the mutex was released on a landed terminal write.
assert_flag_file_absent "$VM_NAME"
# CONTRACT: no boot-loop — the rune NRestarts pathology must not appear.
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 2
# CONTRACT: app healthy at the old version after rollback.
assert_health_passes "$VM_NAME"
# CONTRACT (faithfulness): the erroring migration rolled back, not forward-
# completed — unrecorded in db.migration + file removed (no cell-(e) re-wedge).
_assert_faithful_restore

echo ""
echo "PASS: 3-postswap-migration-deterministic-error (rune wedge FIXED — restores to rolled_back)"
