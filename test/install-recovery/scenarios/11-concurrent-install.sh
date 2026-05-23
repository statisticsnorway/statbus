#!/bin/bash
# Scenario 11: concurrent-install  (C10 / probe 2 live-upgrade refusal)
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
#   - tmp/upgrade-in-progress.json mutex with O_EXCL + PID + flock
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
#     ./test/install-recovery/scenarios/11-concurrent-install.sh \
#     statbus-recovery-11

set -euo pipefail

VM_NAME="${1:-statbus-recovery-11}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
STALL_MAX_WAIT_S="${STALL_MAX_WAIT_S:-300}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
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
echo "  Scenario 11: concurrent-install  (C10 / probe 2 live-upgrade)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

# ─────────────────────────────────────────────────────────────────────────
# Phase 1 — bootstrap + initial install at older release
# ─────────────────────────────────────────────────────────────────────────
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

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
cp /tmp/sb ./sb
chmod +x ./sb
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_INJECT_AT=concurrent-install-attempted-during-migrate-up \
STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE \
STATBUS_MIN_DISK_GB=5 \
    ./sb install --non-interactive --trust-github-user jhf
SCRIPT
scp "${SSH_OPTS[@]}" -q "$INSTALL_SCRIPT" root@"$ip":/tmp/install-c10-first.sh
rm -f "$INSTALL_SCRIPT"

ssh "${SSH_OPTS[@]}" root@"$ip" "
    rm -f /tmp/install-c10-first.exit /tmp/install-c10-first.log
    sudo -u statbus tmux new-session -d -s install-c10-first 'bash -lc \"( bash /tmp/install-c10-first.sh ) > /tmp/install-c10-first.log 2>&1; echo \\\$? > /tmp/install-c10-first.exit\"'
"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — wait for the stall to engage
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for first install's stall to engage ──"
MIGRATE_PID=$(wait_for_inject_stall_ready "$VM_NAME" "$RELEASE_FILE" "$STALL_MAX_WAIT_S" | tee /dev/stderr | tail -1)
if [ -z "$MIGRATE_PID" ]; then
    echo "✗ stall never activated within ${STALL_MAX_WAIT_S}s" >&2
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
SECOND_EXIT=$(VM_EXEC bash -c "
    cd ~/statbus
    ./sb install --non-interactive --trust-github-user jhf > $SECOND_LOG 2>&1
    echo \$?
" 2>/dev/null | tr -d ' \r\n' || echo "?")

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
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@test.service" 2

echo ""
echo "PASS: concurrent-install (probe 2 refused second install; first install completed cleanly)"
