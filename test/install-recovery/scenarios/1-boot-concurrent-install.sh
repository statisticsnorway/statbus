#!/bin/bash
# Scenario: 1-boot-concurrent-install  (C10 / probe 2 live-upgrade refusal)
#
# Class:                 concurrent-install-attempted-during-migrate-up
# Class kind:            Stall
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   The install state machine's probe 2 (live-upgrade) detects an
#   in-flight install via tmp/upgrade-in-progress.json + the holder
#   PID being alive. A SECOND ./sb install run while the first is
#   in its migrate phase MUST refuse with a clear diagnostic naming
#   the holder PID. Only ONE upgrade row is created in
#   public.upgrade; the second install does not produce a row.
#
# Validates fixes already on master:
#   - tmp/upgrade-in-progress.json mutex with flock (LOCK_EX) + PID
#   - probe 2 (live-upgrade) state in install.Detect
#   - the install state ladder's refuse-with-diagnostic path
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2 — provides a
#      migration delta so the first upgrade actually runs migrate.up
#      and hits the existing stall site at the top of runUp).
#   2. Start the first install in detached tmux with
#      STATBUS_INJECT_AT=concurrent-install-attempted-during-migrate-up
#      + STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=<file>.
#   3. Wait for the stall to engage (poll for the flag file
#      + the migrate subprocess being alive).
#   4. Run a SECOND ./sb install without any inject env vars.
#   5. Assert: the second install refuses with a diagnostic that
#      mentions "live-upgrade" (or the holder PID). Exit non-zero.
#   6. Remove release file → first install proceeds → completes.
#   7. Assert: exactly ONE upgrade row exists in public.upgrade.
#
# Hetzner-runnability:
#   READY for Hetzner. Validates probe 2's existing implementation;
#   should go GREEN on the current branch tip without depending on
#   any pending architectural fix.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/1-boot-concurrent-install.sh \
#     statbus-recovery-1-boot-concurrent-install

set -euo pipefail

VM_NAME="${1:-statbus-recovery-1-boot-concurrent-install}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
STALL_MAX_WAIT_S="${STALL_MAX_WAIT_S:-300}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"   # populate_with_demo_data (used to non-fresh the DB so the HEAD install skips its seed)
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

RELEASE_FILE="/tmp/stall-release-c10"
trap '
    rc=$?
    remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE" 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 1-boot-concurrent-install  (C10 / probe 2 live-upgrade)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

# ─────────────────────────────────────────────────────────────────────────
# Phase 1 — bootstrap + initial install at older release
# ─────────────────────────────────────────────────────────────────────────
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION (NO seed — establish a real migration delta) ──"
# NO-SEED baseline: the published seed is dumped at HEAD's migration level, so a
# seeded baseline leaves db.migration already at HEAD → the HEAD "first install"
# below has 0 pending migrations → the Migrations step is skipped (HasPending=false,
# install.go) → migrate.Up never runs → the C10 StallHere never fires → the stall-wait
# times out. SB_INSTALL_SKIP_SEED withholds the release binary's origin/db-seed so this
# baseline lands at INSTALL_VERSION's level (max 20260520141309) instead. (Pure
# harness-side; see install_statbus_in_vm.)
SB_INSTALL_SKIP_SEED=1 install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# Populate demo data so the DB is non-fresh BEFORE the HEAD "first install" below.
# That install is a fresh ./sb install (the step-table path, which DOES run the seed
# step — unlike the upgrade pipeline). On a populated DB, checkSeedRestored's
# dbHasUserData R5 short-circuit (install.go) SKIPS the Docker-image seed, so the HEAD
# install keeps the v<tag>-level baseline and applies the real pending set → migrate.Up
# runs → C10 fires. Without this, the HEAD install would re-seed to HEAD level and
# collapse the delta again.
echo ""
echo "── populating demo data (makes the DB non-fresh so the HEAD install skips its seed) ──"
populate_with_demo_data "$VM_NAME"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — start first install at HEAD with C10 stall env vars
#
# The first install runs through to its migrate phase where the
# existing inject.StallHere("concurrent-install-attempted-during-
# migrate-up") at the top of runUp (cli/internal/migrate/migrate.go)
# blocks. While blocked, the install holds the upgrade-in-progress
# flag with its PID — the live-upgrade signal probe 2 detects.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── creating release file + starting FIRST install at HEAD with C10 injection ──"

VM_EXEC bash -c "touch '$RELEASE_FILE'"

ip=$(hcloud server ip "$VM_NAME")
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
INSTALL_SCRIPT=$(mktemp)
cat > "$INSTALL_SCRIPT" << SCRIPT
set -e
cd ~/statbus
if ! git cat-file -e $HEAD_LOCAL 2>/dev/null; then
    git fetch --depth 1 origin $HEAD_LOCAL || { echo "FATAL: HEAD not on origin" >&2; exit 1; }
fi
git checkout $HEAD_LOCAL
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=concurrent-install-attempted-during-migrate-up \
STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-c10-first.sh
upload_sb_to_vm "$VM_NAME"

ssh "${SSH_OPTS[@]}" statbus@"$ip" "
    rm -f /tmp/install-c10-first.exit /tmp/install-c10-first.log
    tmux new-session -d -s install-c10-first 'bash -lc \"( bash /tmp/install-c10-first.sh ) > /tmp/install-c10-first.log 2>&1; echo \\\$? > /tmp/install-c10-first.exit\"'
"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — wait for the stall to engage
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for first install's stall to engage ──"
# UNMASK: wait_for_inject_stall_ready returns 1 on timeout. Under `set -euo
# pipefail` the `| tee | tail` pipeline propagates that non-zero to the
# assignment → the ERR trap fires "harness failure: rc=1 at tail -1" BEFORE the
# `if [ -z "$MIGRATE_PID" ]` diagnostic can run, hiding WHY the stall never
# engaged. The set +e/set -e fence lets the timeout fall through to the
# diagnostic (install exit code + log tail) below.
set +e
MIGRATE_PID=$(wait_for_inject_stall_ready "$VM_NAME" "$RELEASE_FILE" "$STALL_MAX_WAIT_S" | tee /dev/stderr | tail -1)
set -e
if [ -z "$MIGRATE_PID" ]; then
    echo "✗ stall never activated within ${STALL_MAX_WAIT_S}s" >&2
    echo "  first install exit (if any): $(ssh "${SSH_OPTS[@]}" root@"$ip" "cat /tmp/install-c10-first.exit 2>/dev/null" || echo '(not exited yet)')" >&2
    echo "  last 30 lines of /tmp/install-c10-first.log:" >&2
    ssh "${SSH_OPTS[@]}" root@"$ip" "tail -30 /tmp/install-c10-first.log 2>/dev/null" >&2 || true
    exit 1
fi

# Confirm the flag file exists and capture the holder PID for later
# comparison against the second install's refuse diagnostic.
FIRST_HOLDER=$(VM_EXEC bash -c 'cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null' || echo "")
if [ -z "$FIRST_HOLDER" ]; then
    echo "✗ first install did not create upgrade-in-progress.json" >&2
    exit 1
fi
FIRST_PID=$(echo "$FIRST_HOLDER" | grep -oE '"PID":\s*[0-9]+' | head -1 | grep -oE '[0-9]+' || echo "")
echo "  first install holds flag with PID=$FIRST_PID"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — run SECOND install (no env vars); expect refusal
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── running SECOND install (no env vars) — expecting probe 2 refusal ──"

SECOND_LOG="/tmp/install-c10-second.log"
SECOND_EXIT=$(VM_EXEC bash -c "cd ~/statbus && ./sb install --non-interactive --trust-github-user jhf > $SECOND_LOG 2>&1; echo \$?" 2>/dev/null | tr -d ' \r\n' || echo "?")

echo "  second install exited: $SECOND_EXIT"
SECOND_OUTPUT=$(VM_EXEC bash -c "cat $SECOND_LOG 2>/dev/null" || echo "")
echo "  second install output (tail):"
echo "$SECOND_OUTPUT" | tail -10 | sed 's/^/    /'

# Assertion: second install exits non-zero (refused).
if [ "$SECOND_EXIT" = "0" ]; then
    echo "✗ second install exited 0 (expected refusal)"
    exit 1
fi
echo "  ✓ second install refused with non-zero exit"

# Assertion: refuse diagnostic mentions live-upgrade or the holder PID.
if echo "$SECOND_OUTPUT" | grep -qiE "live-?upgrade|in.progress|PID=$FIRST_PID|holder"; then
    echo "  ✓ second install diagnostic names the live-upgrade / holder PID"
else
    echo "✗ second install diagnostic does NOT mention live-upgrade / holder PID:"
    echo "$SECOND_OUTPUT" | tail -20 | sed 's/^/    /'
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — release the stall, let first install complete
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── releasing stall; first install proceeds ──"
remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE"

echo "  waiting for first install to complete ..."
elapsed=0
poll_s=10
max_iter=$(( INSTALL_BUDGET_S / poll_s ))
FIRST_EXIT=""
for ((i=0; i<max_iter; i++)); do
    if ssh "${SSH_OPTS[@]}" root@"$ip" "test -f /tmp/install-c10-first.exit" 2>/dev/null; then
        FIRST_EXIT=$(ssh "${SSH_OPTS[@]}" root@"$ip" "cat /tmp/install-c10-first.exit" 2>/dev/null | tr -d ' \n')
        break
    fi
    sleep "$poll_s"
    elapsed=$((elapsed + poll_s))
done

if [ -z "$FIRST_EXIT" ]; then
    echo "✗ first install did not complete within ${INSTALL_BUDGET_S}s"
    ssh "${SSH_OPTS[@]}" root@"$ip" "tail -30 /tmp/install-c10-first.log" 2>/dev/null || true
    exit 1
fi
echo "  first install exited: $FIRST_EXIT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

# Only ONE upgrade row created (second install's refusal must not have
# inserted anything into public.upgrade).
UPGRADE_ROW_COUNT=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT count(*) FROM public.upgrade;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  public.upgrade row count: $UPGRADE_ROW_COUNT"
if [ "$UPGRADE_ROW_COUNT" != "1" ]; then
    echo "✗ expected exactly 1 upgrade row; got $UPGRADE_ROW_COUNT"
    exit 1
fi
echo "  ✓ exactly one upgrade row exists (second install correctly refused without inserting)"

assert_upgrade_row_state "$VM_NAME" "completed"
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 1-boot-concurrent-install (probe 2 refused second install; first install completed cleanly)"
