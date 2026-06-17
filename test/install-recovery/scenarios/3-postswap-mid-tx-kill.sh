#!/bin/bash
# Scenario: 3-postswap-mid-tx-kill  (cell b — mid-transaction kill → clean re-apply → completed)
#
# THE GREEN CONTROL for the migrate commit↔record boundary. Its RED siblings
# 3-postswap-migrate-killed-after-commit (cell c) and
# 3-postswap-migration-deterministic-error (cell e) prove the STATBUS-017 wedge;
# this scenario proves the boundary's ONE safe case and that the wedge is
# specific to the after-COMMIT window — not to "any kill during migrate".
#
# WHAT IT PROVES
# ──────────────
# A process killed INSIDE a migration's transaction, BEFORE its COMMIT, leaves
# NO committed-but-unrecorded state: Postgres aborts the uncommitted tx, so the
# migration is cleanly PENDING again. The recovery re-run's schema-skew
# `./sb migrate up` re-applies it cleanly (no "relation already exists"), the
# flag is at Phase=PostSwap (the kill lands in runCrashRecovery's schema-skew
# migrate-up, BEFORE resumePostSwap stamps Resuming — same as cell a/d), so
# recoverFromFlag → resumePostSwap → applyPostSwap → state=completed.
# Contrast cell c/e where a committed-but-unrecorded / always-erroring migration
# makes that same migrate-up FAIL and wedges (STATBUS-017).
#
# THE NEW INJECT POINT (test-only)
# ────────────────────────────────
# A Go-side StallHere/KillHere cannot reach mid-transaction: a migration's whole
# BEGIN…END runs inside the psql subprocess that migrate.runPsqlFile feeds via
# stdin and then blocks reading. So this scenario activates the class
# `killed-by-system-during-migration-tx-before-commit`, which makes
# inject.MidTxPauseSQL splice a `SELECT pg_sleep(...)` INSIDE the migration's
# transaction (after BEGIN, before COMMIT). The migration parks there; the
# harness then kills the process tree AND pg_terminate_backend's the parked
# backend so the open tx aborts regardless of host/docker psql topology.
# Production no-op: env unset → no splice → byte-identical stdin.
#
# REAL MIGRATION DELTA (no-seed lever)
# ────────────────────────────────────
# Baseline installs at v2026.05.2 with SB_INSTALL_SKIP_SEED=1 (engineer-2's
# git-branch seed withhold) so the v2026.05.2→HEAD delta is REAL pending
# migrations. Migration-AGNOSTIC: the pause splices into the FIRST runPsqlFile
# call, so it parks on the first pending migration whichever it is — we kill that
# one. No migration version is hardcoded.
#
# Usage:
#   ./test/install-recovery/scenarios/3-postswap-mid-tx-kill.sh
#
# Optional env:
#   INSTALL_VERSION=v2026.05.2   baseline release (must be < HEAD; provides delta)
#   KEEP_VM=1 / KEEP_VM_ON_FAILURE=1   leave VM up for post-mortem
#   STALL_MAX_WAIT_S=N           per-stall wait budget (default 900)

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-mid-tx-kill}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
STALL_MAX_WAIT_S="${STALL_MAX_WAIT_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

UPGRADE_UNIT="statbus-upgrade@statbus.service"
MIDTX_CLASS="killed-by-system-during-migration-tx-before-commit"
RELEASE_FILE="/tmp/stall-release-midtx"

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-mid-tx-kill  (cell b — GREEN control)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

# ─────────────────────────────────────────────────────────────────────────
# Local helpers
# ─────────────────────────────────────────────────────────────────────────

# Start `./sb install` in a detached tmux session (it PARKS on the mid-tx pause,
# so it cannot be run foreground like the KillHere scenarios). env_prefix is
# inlined so it inherits across syscall.Exec into the migrate-up subprocess.
_start_install_bg() {
    local session="$1" env_prefix="$2" ip
    ip=$(hcloud server ip "$VM_NAME")
    ssh "${SSH_OPTS[@]}" root@"$ip" "
        rm -f /tmp/$session.exit /tmp/$session.log
        sudo -u statbus tmux new-session -d -s $session 'bash -lc \"cd ~/statbus && $env_prefix STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf > /tmp/$session.log 2>&1; echo \\\$? > /tmp/$session.exit\"'
    "
}

# pg_terminate_backend the parked migrate backend (application_name
# 'statbus-migrate-sql%', set by migrate.injectPsqlAppName). Server-side, so it
# aborts the in-tx backend regardless of whether psql is a host client or a
# docker-exec'd in-container client — the open transaction rolls back.
_terminate_migrate_backend() {
    local sql; sql=$(mktemp)
    cat > "$sql" <<'SQL'
SELECT pg_terminate_backend(pid), application_name, state
  FROM pg_stat_activity
 WHERE application_name LIKE 'statbus-migrate-sql%'
   AND pid <> pg_backend_pid();
SQL
    # Pipe the SQL as ssh stdin straight into `./sb psql` as statbus (CLAUDE.md's
    # `ssh host "…psql" < file` pattern; mirrors the assertions). Avoids the
    # scp -O mode-600 root-owned /tmp file the statbus user cannot read.
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" < "$sql" 2>/dev/null || true
    rm -f "$sql"
}

# ─────────────────────────────────────────────────────────────────────────
# Stage 0 — bootstrap + baseline install at v2026.05.2 (NO SEED → real delta)
# ─────────────────────────────────────────────────────────────────────────
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── baseline install at $INSTALL_VERSION (SB_INSTALL_SKIP_SEED=1 → real v2026.05.2→HEAD delta) ──"
SB_INSTALL_SKIP_SEED=1 install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data (R5 catastrophic-loss baseline) ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

BASELINE_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline db.migration max_version: $BASELINE_MAX_VERSION"

# Sanity: the no-seed baseline MUST leave a real pending delta, else the mid-tx
# park never fires. HEAD's on-disk max must exceed the installed max.
HEAD_DISK_MAX=$(ls "$HARNESS_ROOT"/migrations/*.up.sql 2>/dev/null | sed -E 's#.*/([0-9]{14})_.*#\1#' | sort -n | tail -1)
echo "  HEAD on-disk migration max: $HEAD_DISK_MAX"
if [ "$HEAD_DISK_MAX" -le "$BASELINE_MAX_VERSION" ]; then
    echo "✗ no real migration delta (baseline=$BASELINE_MAX_VERSION HEAD=$HEAD_DISK_MAX) — SB_INSTALL_SKIP_SEED did not withhold the seed" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Stage 1 — first install at HEAD; park the FIRST migration mid-tx, then kill
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 1 — first install at HEAD, park first migration mid-tx, SIGKILL tree"
echo "════════════════════════════════════════════════════════════════"

echo "── staging HEAD binary (STATBUS-060: NO checkout — tree stays OLD; executeUpgrade owns the target checkout) ──"
# Pre-fetch HEAD objects only (no checkout) so executeUpgrade's fetch is a fast no-op.
VM_EXEC bash -c "cd ~/statbus && git fetch --depth 1 origin $HEAD_SHA"
VM_EXEC bash -c "cd ~/statbus && cp /tmp/env-config .env.config && cp /tmp/users.yml .users.yml"

# Fabricate BEFORE upload_sb_to_vm so fabricate's `./sb config generate` runs the
# OLD v2026.05.2 binary on the OLD tree (matched → no freshness self-heal trip),
# mirroring the reference model (2-preswap-checkout-kill).
echo "── fabricating scheduled public.upgrade row for HEAD ──"
quiesce_upgrade_service "$VM_NAME"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_SHA"

upload_sb_to_vm "$VM_NAME"

echo "── triggering install with mid-tx pause injection ──"
VM_EXEC bash -c "touch '$RELEASE_FILE'"
ENV_PREFIX="STATBUS_INJECT_AT=$MIDTX_CLASS STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE"
_start_install_bg "midtx" "$ENV_PREFIX"

echo "── waiting for the migration to park mid-tx ──"
# On the inline dispatch path (./sb install → executeUpgrade inline), there is NO
# separate `./sb migrate up` subprocess.  wait_for_inject_stall_ready (which polls
# pgrep /sb migrate up) would time out immediately.  Use wait_for_midtx_stall_ready
# instead — it polls pg_stat_activity for the parked psql backend.
# Fence with || true: under set -euo pipefail, a pipeline where the first command
# exits non-zero (timeout) would propagate rc=1 through tail -1 and abort the
# script before the emptiness check below gets a chance to report the real error.
MIGRATE_PID=$(wait_for_midtx_stall_ready "$VM_NAME" "$STALL_MAX_WAIT_S" | tee /dev/stderr | tail -1) || true
if [ -z "$MIGRATE_PID" ]; then
    echo "✗ mid-tx park never activated" >&2
    exit 1
fi
echo "  migrate subprocess parked (PID=$MIGRATE_PID)"

# RED shape while parked: the migration's tx is OPEN and uncommitted, so
# db.migration max has NOT bumped (the first pending migration has not committed).
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"

# KILL the process tree FIRST (install parent + migrate subprocess) with SIGKILL
# so the upgrade cannot catch the failure and run its own graceful rollback — we
# want the OS-kill shape (flag pinned PostSwap, recovered by the NEXT install).
PARENT_PID=$(pgrep_upgrade_service_parent "$VM_NAME")
echo "  upgrade-service parent PID=$PARENT_PID; SIGKILL tree (parent + migrate)"
[ -n "$PARENT_PID" ] && kill_pid_in_vm "$VM_NAME" "$PARENT_PID" KILL
kill_pid_in_vm "$VM_NAME" "$MIGRATE_PID" KILL

# The SIGKILL'd Go processes orphan the still-sleeping psql backend holding the
# open tx; pg_terminate_backend aborts it server-side → the tx rolls back.
echo "── aborting the parked migrate backend (pg_terminate_backend) ──"
_terminate_migrate_backend
remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE"

# ─────────────────────────────────────────────────────────────────────────
# Stage 2 — verify the clean RED shape (no committed-but-unrecorded state)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── verifying clean mid-tx RED shape ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" >/dev/null || {
    echo "✗ expected flag file present after kill" >&2; exit 1; }
assert_upgrade_row_state "$VM_NAME" "in_progress"
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"
echo "  ✓ RED confirmed: flag present, row in_progress, tx rolled back (db.migration unbumped, NO committed-unrecorded)"

# ─────────────────────────────────────────────────────────────────────────
# Stage 3 — second install for recovery → clean re-apply → completed
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second install for recovery (clean re-apply, NO inject) ──"
install_statbus_in_vm "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Stage 4 — GREEN convergence (this PASSES — cell b is the safe case)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks (GREEN) ──"
assert_upgrade_row_state "$VM_NAME" "completed"

POST_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  post-recovery db.migration max_version: $POST_MAX_VERSION"
if [ "$POST_MAX_VERSION" -le "$BASELINE_MAX_VERSION" ]; then
    echo "✗ db.migration max_version did NOT advance (baseline=$BASELINE_MAX_VERSION post=$POST_MAX_VERSION) — recovery did not re-apply the killed migration" >&2
    exit 1
fi
echo "  ✓ db.migration max_version advanced ($BASELINE_MAX_VERSION → $POST_MAX_VERSION) — the killed migration re-applied cleanly"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 2

echo ""
echo "PASS: 3-postswap-mid-tx-kill (mid-tx kill rolled back cleanly, forward-recovery completed the upgrade)"
