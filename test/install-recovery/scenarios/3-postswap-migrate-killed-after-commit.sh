#!/bin/bash
# Scenario: 3-postswap-migrate-killed-after-commit
#
# Validates the principled forward-then-restore recovery path against
# the canonical case: a process killed in the ~ms window between a
# migration's outer-transaction commit and the db.migration INSERT.
# Forward-recovery on this state fails deterministically ("relation
# already exists" on re-attempt); only rsync-restore can complete
# recovery coherently. Mirrors rune's exact failure shape — what
# triggered the original wedge.
#
# Two stages exercise the two recovery layers:
#
#   Stage 1 — subprocess-killed (Layer 0 in-process recovery)
#     - Set STATBUS_INJECT_AT=migrate-subprocess-killed-after-commit-
#       before-recorded with a release file.
#     - Trigger upgrade. inject.StallHere in the new binary's
#       migrate.runUp holds the migrate SUBPROCESS at the canonical
#       point (after commit, before INSERT INTO db.migration).
#     - Harness sends real SIGKILL to the migrate subprocess.
#     - Parent applyPostSwap sees subprocess exit, calls
#       postSwapFailure → d.rollback() → rsync-restore → row='rolled_back'
#       with the augmented "forward failed: <err>; auto-restored from
#       <path>" narrative.
#
#   Stage 2 — parent-killed (Layer 2 next-install recovery)
#     - Set STATBUS_INJECT_AT=upgrade-service-parent-killed-after-
#       commit-before-recorded with a release file.
#     - Trigger upgrade. Same stall site.
#     - Harness sends real SIGKILL to the upgrade-service PARENT (the
#       ./sb install process running executeUpgrade inline). Also
#       SIGKILLs the now-orphan migrate subprocess to prevent it from
#       resuming when the release file is removed.
#     - System state: flag file present, latest public.upgrade row
#       state='in_progress', partial migration committed in DB,
#       db.migration max version unchanged → canonical Layer 2 RED.
#     - Run a second `./sb install` (no env vars). State-ladder probe 3
#       (crashed-upgrade) fires → recoverFromFlag → forward-recovery
#       via migrate.Up → fails on "relation already exists" → falls
#       through to rsync-restore → row='rolled_back' with the same
#       augmented narrative.
#
# Both stages converge on the same terminal: row='rolled_back', flag
# absent, no orphan pre-upgrade-* backup, services healthy at the
# pre-upgrade version. The two stages differ only in WHICH layer ran
# the recovery.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 \
#     ./test/install-recovery/scenarios/3-postswap-migrate-killed-after-commit.sh
#
# Optional env:
#   KEEP_VM=1            Leave VM running on failure for debugging
#   STALL_MAX_WAIT_S=N   Override the per-stall wait budget (default 300s)

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-migrate-killed-after-commit}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"  # must be older than HEAD; provides migration delta
STALL_MAX_WAIT_S="${STALL_MAX_WAIT_S:-300}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-migrate-killed-after-commit"
echo "  Initial release: $INSTALL_VERSION → Upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
HEAD_SHORT="${HEAD_SHA:0:8}"
echo "  HEAD: $HEAD_SHA ($HEAD_SHORT)"

# ─────────────────────────────────────────────────────────────────────────
# Stage 0 — bootstrap + initial install
# ─────────────────────────────────────────────────────────────────────────
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# Fetch HEAD into the VM so the upgrade-pipeline's git checkout can find
# it. The local repo's HEAD is on engineer/upgrade-recovery-validation,
# already pushed to origin.
echo "── fetching HEAD into VM ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $HEAD_SHA"

# Snapshot baseline db.migration max version. Both stages' partial-state
# checks confirm this number does NOT bump during the stall window.
BASELINE_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' ')
echo "  baseline db.migration max_version = $BASELINE_MAX_VERSION"

# ─────────────────────────────────────────────────────────────────────────
# Shared helper: start install in detached tmux with env-var injection.
# Returns the tmux session name (caller polls/intervenes asynchronously).
# ─────────────────────────────────────────────────────────────────────────
_start_install_with_env() {
    local session="$1"
    local env_prefix="$2"  # e.g. "STATBUS_INJECT_AT=foo STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=/tmp/x"
    local ip
    ip=$(hcloud server ip "$VM_NAME")

    # First install populated ~/statbus + ~/statbus/sb. Subsequent installs
    # re-run from the same dir. The env_prefix is inlined into the exec line
    # so it lands in the executeUpgrade process tree (and inherits through
    # syscall.Exec across binary swap + into the migrate-up subprocess).
    ssh "${SSH_OPTS[@]}" root@"$ip" "
        rm -f /tmp/$session.exit /tmp/$session.log
        sudo -u statbus tmux new-session -d -s $session 'bash -lc \"cd ~/statbus && $env_prefix STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf > /tmp/$session.log 2>&1; echo \\\$? > /tmp/$session.exit\"'
    "
}

# Wait for the tmux install session to exit and return its exit code.
_wait_install_exit() {
    local session="$1"
    local max_min="${2:-15}"
    local ip
    ip=$(hcloud server ip "$VM_NAME")
    local max_iter=$(( max_min * 60 / 5 )) i seen=0
    for ((i=0; i<max_iter; i++)); do
        if ssh "${SSH_OPTS[@]}" root@"$ip" "test -f /tmp/$session.exit" 2>/dev/null; then
            local cur exit_code
            cur=$(ssh "${SSH_OPTS[@]}" root@"$ip" "wc -l < /tmp/$session.log 2>/dev/null" 2>/dev/null | tr -d ' ')
            if [ -n "$cur" ] && [ "$cur" -gt "$seen" ] 2>/dev/null; then
                ssh "${SSH_OPTS[@]}" root@"$ip" "tail -n $((cur - seen)) /tmp/$session.log" 2>/dev/null
            fi
            exit_code=$(ssh "${SSH_OPTS[@]}" root@"$ip" "cat /tmp/$session.exit" 2>/dev/null | tr -d ' \n')
            echo "  install ($session) exited: $exit_code"
            return 0
        fi
        local cur
        cur=$(ssh "${SSH_OPTS[@]}" root@"$ip" "wc -l < /tmp/$session.log 2>/dev/null" 2>/dev/null | tr -d ' ')
        if [ -n "$cur" ] && [ "$cur" -gt "$seen" ] 2>/dev/null; then
            ssh "${SSH_OPTS[@]}" root@"$ip" "tail -n $((cur - seen)) /tmp/$session.log" 2>/dev/null
            seen="$cur"
        fi
        sleep 5
    done
    echo "  WARNING: install ($session) did not exit within ${max_min} min" >&2
    return 1
}

# ─────────────────────────────────────────────────────────────────────────
# Stage 1 — subprocess-killed
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 1 — subprocess-killed (Layer 0 in-process recovery)"
echo "════════════════════════════════════════════════════════════════"

RELEASE_FILE_1="/tmp/stall-release-stage1"
VM_EXEC bash -c "touch '$RELEASE_FILE_1'"

echo "── fabricating scheduled public.upgrade row for HEAD ($HEAD_SHA) ──"
# HEAD is untagged — ./sb upgrade schedule only accepts CalVer release tags and
# UPDATEs existing 'available' rows; it cannot schedule an untagged commit.
# fabricate_scheduled_upgrade_row inserts a 'scheduled' row directly so
# ./sb install detects it and dispatches executeUpgrade.
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_SHA"

echo "── triggering install with subprocess-stall injection ──"
ENV1="STATBUS_INJECT_AT=migrate-subprocess-killed-after-commit-before-recorded STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE_1"
_start_install_with_env "stage1" "$ENV1"

# Wait for the stall to be active. wait_for_inject_stall_ready prints
# the migrate subprocess PID on stdout when it returns 0.
echo "── waiting for stall ──"
MIGRATE_PID=$(wait_for_inject_stall_ready "$VM_NAME" "$RELEASE_FILE_1" "$STALL_MAX_WAIT_S" | tee /dev/stderr | tail -1)
if [ -z "$MIGRATE_PID" ]; then
    echo "✗ stage 1: stall never activated" >&2
    exit 1
fi

# Confirm partial state shape (committed migration's effects in DB, but
# db.migration record not yet INSERTed).
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"

# Real SIGKILL to the migrate subprocess (not os.Exit — see commit
# message for the canonical-stall design rationale).
kill_pid_in_vm "$VM_NAME" "$MIGRATE_PID" KILL

# Release file no longer needed (subprocess is dead). Remove for hygiene
# so a future StallHere in the same VM run doesn't see a stale file.
remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE_1"

# Wait for parent applyPostSwap to run postSwapFailure → d.rollback() →
# row marked rolled_back → flag cleared → install process exits.
echo "── waiting for parent in-process recovery ──"
_wait_install_exit "stage1" 20 || true   # exit code expected non-zero; rollback completed but install reports failure

# Convergence checks
echo "── stage 1 convergence ──"
assert_upgrade_row_state "$VM_NAME" "rolled_back"
assert_upgrade_row_error_matches "$VM_NAME" "forward failed: .*; auto-restored from"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "✓ Stage 1 passed (Layer 0 in-process recovery via postSwapFailure)"

# ─────────────────────────────────────────────────────────────────────────
# Stage 2 — parent-killed
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2 — parent-killed (Layer 2 next-install recovery)"
echo "════════════════════════════════════════════════════════════════"

# System is now back at $INSTALL_VERSION (stage 1 rolled back to it).
# Re-snapshot baseline (should match the original baseline since rollback
# restored from the pre-upgrade DB dump).
BASELINE_MAX_VERSION=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT COALESCE(MAX(version), 0) FROM db.migration;' | ./sb psql -t -A" 2>/dev/null | tr -d ' ')
echo "  re-baselined db.migration max_version = $BASELINE_MAX_VERSION"

RELEASE_FILE_2="/tmp/stall-release-stage2"
VM_EXEC bash -c "touch '$RELEASE_FILE_2'"

echo "── fabricating fresh scheduled public.upgrade row for HEAD ($HEAD_SHA) ──"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_SHA"

echo "── triggering install with parent-stall injection ──"
ENV2="STATBUS_INJECT_AT=upgrade-service-parent-killed-after-commit-before-recorded STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE_2"
_start_install_with_env "stage2" "$ENV2"

echo "── waiting for stall ──"
MIGRATE_PID=$(wait_for_inject_stall_ready "$VM_NAME" "$RELEASE_FILE_2" "$STALL_MAX_WAIT_S" | tee /dev/stderr | tail -1)
if [ -z "$MIGRATE_PID" ]; then
    echo "✗ stage 2: stall never activated" >&2
    exit 1
fi

assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"

# Identify the upgrade-service PARENT (the ./sb install Go process
# running executeUpgrade inline). pgrep_upgrade_service_parent uses
# pgrep -nf to get the most recently started match — that's the
# install we just kicked off.
PARENT_PID=$(pgrep_upgrade_service_parent "$VM_NAME")
echo "  upgrade-service parent PID=$PARENT_PID"

# SIGKILL the PARENT first so it can't catch the subprocess's death and
# run postSwapFailure (which would defeat the Layer 2 test). Then KILL
# the subprocess to prevent it from resuming once the release file is
# removed.
kill_pid_in_vm "$VM_NAME" "$PARENT_PID" KILL
kill_pid_in_vm "$VM_NAME" "$MIGRATE_PID" KILL

remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE_2"

# Verify the canonical RED shape on disk + in DB before the recovery run.
echo "── verifying canonical RED state ──"
VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after parent SIGKILL" >&2
    exit 1
}
assert_upgrade_row_state "$VM_NAME" "in_progress"
assert_db_migration_max_version_unchanged "$VM_NAME" "$BASELINE_MAX_VERSION"
echo "  ✓ RED confirmed: flag present, row in_progress, partial migration unbumped"

# Layer 2: run a second `./sb install` with NO env vars. State-ladder
# probe 3 (crashed-upgrade) fires → recoverFromFlag → forward attempt
# fails on "relation already exists" → falls through to rsync-restore.
echo "── running second install for Layer 2 recovery ──"
install_statbus_in_vm "$VM_NAME"

# Convergence checks (same as stage 1)
echo "── stage 2 convergence ──"
assert_upgrade_row_state "$VM_NAME" "rolled_back"
assert_upgrade_row_error_matches "$VM_NAME" "forward failed: .*; auto-restored from"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "✓ Stage 2 passed (Layer 2 next-install recovery via recoverFromFlag)"

echo ""
echo "PASS: 3-postswap-migrate-killed-after-commit"
