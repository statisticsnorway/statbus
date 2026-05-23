#!/bin/bash
# Scenario 02: happy-upgrade  (baseline — no failure injection)
#
# Class:                 N/A (baseline regression net for the happy path)
# Class kind:            N/A — no inject site fires
# Source forensics:      tmp/install-state-machine-forensics.md
#                        (the implicit complement to every failure scenario)
#
# Expected principled behavior:
#   The supervised, unattended upgrade path — install at an older
#   release → populate data → schedule upgrade to HEAD → wait for
#   the upgrade-service unit's poll tick to dispatch + run
#   executeUpgrade → applyPostSwap to completion — must converge
#   to a healthy state with data intact. This is the BASELINE
#   regression net that catches any change that makes the normal
#   upgrade path break, independent of any failure-injection
#   scenario.
#
#   The unattended path differs from the inline `./sb install` path
#   used by scenarios 12+/15+/16+/17+/21+/22+/23+/24 in one
#   important way: the upgrade-service systemd unit dispatches the
#   upgrade against the supervised WatchdogSec + TimeoutStopSec
#   budgets. A regression in the unit's notify-protocol wiring
#   (e.g., a missed WATCHDOG=1 or READY=1) would show up here
#   first, even if the inline tests are all green.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (v2026.05.2). Verify health.
#   2. Populate via populate_with_demo_data. Snapshot data counts.
#   3. Stage HEAD on the VM (git fetch + checkout HEAD; copy
#      HEAD's sb binary to ~/statbus/sb). The unit will use HEAD's
#      code to dispatch the upgrade once it picks up a scheduled
#      row. Baseline NRestarts before triggering.
#   4. Use `./sb upgrade apply <HEAD-SHA>` to write a scheduled
#      row + NOTIFY the upgrade-service. Per the discover machinery
#      that runs on the service's tick, the row will be acted on.
#      (If `./sb upgrade apply` requires the SHA to be in
#      `public.upgrade` already as 'available', the discover step
#      runs first via the service's poll tick — this scenario waits
#      one tick before issuing `apply`.)
#   5. Wait for the upgrade row to reach a terminal state
#      (completed | failed | rolled_back) — happy path expectation
#      is `completed`.
#   6. Assert convergence: state='completed', data intact, services
#      healthy, NRestarts delta ≤ 2 (no watchdog or start-timeout
#      tripped during the normal upgrade).
#
# Hetzner-runnability:
#   READY. No injection site needed. This is the baseline that all
#   other scenarios assume holds — if it fails, the upgrade-service's
#   notify protocol or the inline-vs-supervised dispatch path has
#   diverged.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/02-happy-upgrade.sh \
#     statbus-recovery-02

set -euo pipefail

VM_NAME="${1:-statbus-recovery-02}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-90}"   # > default tick interval (60s) + slack

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 02: happy-upgrade  (baseline — supervised unattended path)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-upgrade data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# Verify upgrade-service unit is active before we start.
UNIT_STATE_BEFORE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@test.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE_BEFORE" != "active" ]; then
    echo "✗ upgrade-service unit not active before upgrade trigger (state=$UNIT_STATE_BEFORE)" >&2
    exit 1
fi
echo "  ✓ upgrade-service active before trigger"

NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "statbus-upgrade@test.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — stage HEAD on the VM (git + sb binary)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── staging HEAD on the VM ──"
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
ip=$(hcloud server ip "$VM_NAME")

VM_EXEC bash -c "
    cd ~/statbus
    if ! git cat-file -e $HEAD_LOCAL 2>/dev/null; then
        git fetch --depth 1 origin $HEAD_LOCAL || { echo 'FATAL' >&2; exit 1; }
    fi
    git checkout $HEAD_LOCAL
    cp /tmp/sb ./sb
    chmod +x ./sb
"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — wait one upgrade-service tick so discover populates
# public.upgrade with HEAD's commit as state='available'.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting ${TICK_WAIT_S}s for upgrade-service discover tick to populate public.upgrade ──"
sleep "$TICK_WAIT_S"

# Confirm discover saw HEAD (or at least an available row matching the
# commit). If discover didn't find HEAD (e.g. HEAD is unrelated to a
# release tag), the schedule below will fail.
AVAILABLE_COUNT=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.upgrade WHERE commit_sha = '$HEAD_SHA' AND state = 'available';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  available rows matching HEAD: $AVAILABLE_COUNT"
if [ "$AVAILABLE_COUNT" = "0" ]; then
    echo "  NOTE: discover did not surface HEAD as 'available' — likely because HEAD is not on a release tag."
    echo "  Falling back to: insert the row directly via ./sb upgrade apply, which writes 'scheduled' regardless."
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — trigger upgrade via `./sb upgrade apply <sha>` (NOTIFY)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── triggering upgrade via ./sb upgrade apply ──"
SHORT_SHA=$(echo "$HEAD_SHA" | cut -c1-8)
VM_EXEC bash -c "
    cd ~/statbus
    ./sb upgrade apply $SHORT_SHA 2>&1 | tail -20 || {
        echo 'FATAL: upgrade apply failed — discover may not have populated the available row.' >&2
        echo 'SELECT id, state, commit_sha, commit_version FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql >&2
        exit 1
    }
"

# Wait for the row to transition to in_progress, then to a terminal state.
echo ""
echo "── waiting for upgrade to reach in_progress, then terminal state ──"
START_TS=$(date +%s)
SAW_IN_PROGRESS=0
FINAL_STATE=""

while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$UPGRADE_BUDGET_S" ]; then
        echo "✗ upgrade did not reach terminal state within ${UPGRADE_BUDGET_S}s" >&2
        VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, commit_sha, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_SHA' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    case "$STATE" in
        in_progress)
            if [ "$SAW_IN_PROGRESS" = "0" ]; then
                echo "  ✓ upgrade in_progress (t+${elapsed}s)"
                SAW_IN_PROGRESS=1
            fi
            ;;
        completed|failed|rolled_back)
            FINAL_STATE="$STATE"
            echo "  ✓ upgrade reached state='$STATE' (t+${elapsed}s)"
            break
            ;;
    esac
    if [ $((elapsed % 30)) -eq 0 ] && [ "$elapsed" -gt 0 ]; then
        echo "    [t+${elapsed}s] state=$STATE"
    fi
    sleep 5
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# Happy path: state MUST be 'completed'. Anything else is a regression.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

if [ "$FINAL_STATE" != "completed" ]; then
    echo "✗ happy-upgrade did NOT reach state='completed' (got '$FINAL_STATE')" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$HEAD_SHA' ORDER BY id DESC LIMIT 3;\" | ./sb psql" >&2 || true
    exit 1
fi
echo "  ✓ state='completed'"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

# Bounded restarts. The normal upgrade should NOT have triggered any
# watchdog or start-timeout — NRestarts ought to stay at baseline.
NRESTARTS_FINAL=$(VM_EXEC systemctl --user show "statbus-upgrade@test.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESTART_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$RESTART_DELTA"
if [ "$RESTART_DELTA" -gt 2 ]; then
    echo "✗ NRestarts grew by $RESTART_DELTA during a happy upgrade — unit was unstable" >&2
    exit 1
fi
echo "  ✓ restart counter bounded"

echo ""
echo "PASS: happy-upgrade (supervised unattended path completed cleanly; data intact; unit stable)"
