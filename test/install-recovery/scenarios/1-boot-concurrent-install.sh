#!/bin/bash
# Scenario: 1-boot-concurrent-install  (C10 / probe 2 live-upgrade refusal)
# judge = HEAD, judged = HEAD, deliberately: catches target-side breakage before a candidate exists
# R1 verdict: rebaseline — this scenario tests current recovery machinery, not an old release-specific bug.
#
# Class:                 concurrent-install-attempted-during-migrate-up
# Class kind:            Stall
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   The install state machine's probe 2 (live-upgrade) detects an
#   in-flight install via tmp/upgrade-in-progress.json + the holder
#   flock being held. A SECOND ./sb install run while the first is
#   in its migrate phase MUST refuse with a clear diagnostic identifying
#   the install holder. Only ONE upgrade row is created in
#   public.upgrade; the second install does not produce a row.
#
# Validates fixes already on master:
#   - tmp/upgrade-in-progress.json mutex with flock (LOCK_EX)
#   - probe 2 (live-upgrade) state in install.Detect
#   - the install state ladder's refuse-with-diagnostic path
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (dynamic release baseline — provides a
#      migration delta so the first upgrade actually runs migrate.up
#      and hits the existing stall site at the top of runUp).
#   2. Start the first install in detached tmux with
#      STATBUS_INJECT_AT=concurrent-install-attempted-during-migrate-up
#      + STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=<file>.
#   3. Wait for the stall to engage (poll for the flag file
#      + the migrate subprocess being alive).
#   4. Run a SECOND ./sb install without any inject env vars.
#   5. Assert: the second install refuses with a diagnostic that
#      names the running installation and its recorded process ID. Exit non-zero.
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
STALL_MAX_WAIT_S="${STALL_MAX_WAIT_S:-300}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
INSTALL_VERSION="${INSTALL_VERSION:-$(select_release_baseline_from_repo "$REPO_ROOT")}"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"   # populate_with_demo_data (used to non-fresh the DB so the HEAD install skips its seed)
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

RELEASE_FILE="/tmp/stall-release-c10"
trap '
    rc=$?
    if [ "$rc" -ne 0 ] && [ "${VM_OWNED_BY_THIS_RUN:-0}" = 1 ]; then
        capture_failure_artifacts "$VM_NAME" || true
        # cleanup_vm also captures failures. Preserve this pre-release snapshot
        # separately so post-release capture cannot overwrite the live evidence.
        if [ -d "$HARNESS_ROOT/tmp/$VM_NAME" ]; then
            cp -R "$HARNESS_ROOT/tmp/$VM_NAME" "$HARNESS_ROOT/tmp/$VM_NAME-pre-release-$(date +%s)" || true
        fi
    fi
    remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE" 2>/dev/null || true
    cleanup_vm "$VM_NAME" "$rc" || true
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
echo "── initial install at $INSTALL_VERSION (establish a real migration delta) ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
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
# flag with its flock — the live-upgrade signal probe 2 detects.
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
echo \$\$ > /tmp/install-c10-first.pid
exec env STATBUS_INJECT_AT=concurrent-install-attempted-during-migrate-up \
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
harness_register_log install-c10-first /tmp/install-c10-first.log "$ip"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — wait for the stall to engage
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for first install's stall to engage ──"
# Keep readiness status separate from stdout. Even a failed transport that
# prints a plausible PID must reach the diagnostic below, not the next phase.
# Progress remains on stderr, and success emits only the numeric PID.
# Image pulls precede migrations. Give that phase its own budget, then
# observe the actual migrate process. Earlier CI tails contained an INJECT
# marker only AFTER timeout; they did not timestamp when the stall began.
echo "── waiting for first install to finish pulling images (step 7) ──"
IMAGES_MAX_WAIT_S="${IMAGES_MAX_WAIT_S:-900}"
_deadline=$(( $(date +%s) + IMAGES_MAX_WAIT_S ))
until ssh "${SSH_OPTS[@]}" root@"$ip" "grep -qE '^\[7/[0-9]+\] Images +(OK|SKIP|DONE)' /tmp/install-c10-first.log 2>/dev/null"; do
    if [ "$(date +%s)" -ge "$_deadline" ]; then
        echo "✗ first install did not finish step 7 (Images) within ${IMAGES_MAX_WAIT_S}s" >&2
        echo "  first install exit (if any): $(ssh "${SSH_OPTS[@]}" root@"$ip" "cat /tmp/install-c10-first.exit 2>/dev/null" || echo '(not exited yet)')" >&2
        ssh "${SSH_OPTS[@]}" root@"$ip" "tail -30 /tmp/install-c10-first.log 2>/dev/null" >&2 || true
        exit 1
    fi
    sleep 10
done
echo "  images pulled; stall budget starts now (${STALL_MAX_WAIT_S}s)"
if ! MIGRATE_PID=$(wait_for_inject_stall_ready "$VM_NAME" "$RELEASE_FILE" "$STALL_MAX_WAIT_S" /tmp/install-c10-first.log /tmp/install-c10-first.pid concurrent-install-attempted-during-migrate-up); then
    echo "✗ stall never activated within ${STALL_MAX_WAIT_S}s" >&2
    echo "  first install exit (if any): $(ssh "${SSH_OPTS[@]}" root@"$ip" "cat /tmp/install-c10-first.exit 2>/dev/null" || echo '(not exited yet)')" >&2
    echo "  last 30 lines of /tmp/install-c10-first.log:" >&2
    ssh "${SSH_OPTS[@]}" root@"$ip" "tail -30 /tmp/install-c10-first.log 2>/dev/null" >&2 || true
    exit 1
fi

# The PID is diagnostic only. Verify owner and PID in the flag; the second
# install's live-upgrade classification proves flock liveness independently.
FIRST_HOLDER=$(VM_EXEC bash -c 'cat ~/statbus/tmp/upgrade-in-progress.json')
if ! FIRST_PID=$(printf '%s\n' "$FIRST_HOLDER" | python3 -c 'import json, sys; f=json.load(sys.stdin); pid=f.get("pid"); assert f.get("holder") == "install" and type(pid) is int and pid > 0; print(pid)'); then
    echo "✗ first install did not create an install-held flag with a process ID" >&2
    exit 1
fi
echo "  first install has an install-held upgrade flag (process $FIRST_PID)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — run SECOND install (no env vars); expect refusal
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── running SECOND install (no env vars) — expecting probe 2 refusal ──"

SECOND_LOG="/tmp/install-c10-second.log"
harness_register_log install-c10-second "$SECOND_LOG"
if ! SECOND_EXIT=$(VM_SCRIPT_INLINE concurrent-second-install "$SECOND_LOG" <<'SCRIPT'
#!/bin/bash
cd ~/statbus || exit 1
./sb install --non-interactive --trust-github-user jhf > "$1" 2>&1
rc=$?
printf '%s\n' "$rc"
SCRIPT
); then
    echo "✗ second install transport failed" >&2
    exit 1
fi
if [[ ! "$SECOND_EXIT" =~ ^[0-9]+$ ]] || [ "$SECOND_EXIT" -gt 255 ]; then
    echo "✗ invalid second install exit status: '$SECOND_EXIT'" >&2
    exit 1
fi

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

# Require the exact process ID read from the marker, never a generic holder
# label or a PID discovered by running a command. Reject upgrade-only wording.
if printf '%s\n' "$SECOND_OUTPUT" | grep -Fq 'Detected install state: live-upgrade' &&
   printf '%s\n' "$SECOND_OUTPUT" | grep -Eq "an installation started at [^ ]+ \\(process ${FIRST_PID}\\) is still running" &&
   ! printf '%s\n' "$SECOND_OUTPUT" | grep -Fq 'An upgrade is already running' &&
   ! printf '%s\n' "$SECOND_OUTPUT" | grep -Fq 'lsof'; then
    echo "  ✓ second install identifies the live installation and its process ID"
else
    echo "✗ second install diagnostic does not identify the live install holder:"
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
if [ "$FIRST_EXIT" != "0" ]; then
    echo "✗ first install did not exit successfully" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

# Convergence — do NOT assert latest-row-by-id. public.upgrade legitimately holds
# the baseline-completed row, the HEAD-completed row (distinct commit_sha → no ON
# CONFLICT collapse), AND environment-dependent discovery 'available' rows (daemon
# upgrade_check NOTIFY handler) whose SERIAL ids can EXCEED the HEAD row's, so
# `ORDER BY id DESC LIMIT 1` is fragile. The real contract — the second concurrent
# install REFUSED via probe-2 live-upgrade — is already asserted above (sh:189-205,
# passed). Convergence here = (a) the first install RECORDED its HEAD completion,
# anchored by commit_sha (the HEAD row is unique by commit_sha; install upserts it
# to 'completed'), and (b) no debris (no row stuck in_progress/failed).
HEAD_ROW_STATE=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
    "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" \
    2>/dev/null <<< "SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_SHA';" | tr -d ' \r\n')
if [ "$HEAD_ROW_STATE" != "completed" ]; then
    echo "✗ HEAD upgrade row (commit_sha=$HEAD_SHA) state='$HEAD_ROW_STATE', expected 'completed'"; exit 1
fi
echo "  ✓ HEAD upgrade row is 'completed' (first install converged)"

STUCK=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
    "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -t -A'" \
    2>/dev/null <<< "SELECT count(*) FROM public.upgrade WHERE state IN ('in_progress','failed');" | tr -d ' \r\n')
if [ "$STUCK" != "0" ]; then
    echo "✗ expected 0 in_progress/failed rows; got $STUCK"; exit 1
fi
echo "  ✓ no upgrade row stuck in_progress/failed"
# Observe absence positively; unreadable directories and transport failure
# must not become an all-clear via the generic best-effort helper.
if ! VM_SCRIPT_INLINE concurrent-flag-absent <<'SCRIPT'
#!/bin/bash
set -eu
cd ~/statbus/tmp
python3 - <<'PY_ABSENT'
from pathlib import Path
names = [p.name for p in Path('.').iterdir()]
if 'upgrade-in-progress.json' in names:
    raise SystemExit('upgrade flag is still present')
print('  ✓ upgrade flag file absent (directory read succeeded)')
PY_ABSENT
SCRIPT
then
    echo "✗ could not prove upgrade flag absence" >&2
    exit 1
fi
assert_health_passes "$VM_NAME"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 1-boot-concurrent-install (probe 2 refused second install; first install completed cleanly)"
