#!/bin/bash
# Scenario: 0-happy-upgrade  (baseline — no failure injection)
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
#   4. Register HEAD as an upgrade candidate via `./sb upgrade register
#      <HEAD-SHA>` (the real post-086 verb — the box is already at HEAD's
#      binary), then wait for it to reach 'ready' (register → ready).
#   5. Schedule it via `./sb upgrade schedule <HEAD-SHA>`; the DB trigger
#      NOTIFYs the upgrade-service, which claims + runs executeUpgrade.
#      Wait for the upgrade row to reach a terminal state
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
#     ./test/install-recovery/scenarios/0-happy-upgrade.sh \
#     statbus-recovery-0-happy-upgrade

set -euo pipefail

VM_NAME="${1:-statbus-recovery-0-happy-upgrade}"
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
echo "  Scenario: 0-happy-upgrade  (baseline — supervised unattended path)"
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
UNIT_STATE_BEFORE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE_BEFORE" != "active" ]; then
    echo "✗ upgrade-service unit not active before upgrade trigger (state=$UNIT_STATE_BEFORE)" >&2
    exit 1
fi
echo "  ✓ upgrade-service active before trigger"

NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — stage HEAD on the VM (git + sb binary)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── staging HEAD on the VM ──"
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
ip=$(hcloud server ip "$VM_NAME")
upload_sb_to_vm "$VM_NAME"

# Single-line: printf '%q' converts multi-line strings to ANSI-C $'...\n...' quoting,
# but the remote /bin/sh (dash on Ubuntu) does not expand $'...' — newlines collapse,
# breaking if/then/fi syntax.  Semicolons replace newlines; if COND; then CMD; fi
# is valid single-line bash.
VM_EXEC bash -c "cd ~/statbus && if ! git cat-file -e $HEAD_LOCAL 2>/dev/null; then git fetch --depth 1 origin $HEAD_LOCAL || { echo 'FATAL: cannot fetch HEAD' >&2; exit 1; }; fi && git checkout $HEAD_LOCAL"

# Restart the upgrade-service unit so it re-execs the freshly pre-staged HEAD
# binary. upload_sb_to_vm (above) atomically swaps ~/statbus/sb via mv-then-cp,
# so the STILL-RUNNING service keeps its OLD INSTALL_VERSION inode until restarted.
# That matters: the install-version binary PREDATES buildBinaryOnDisk's pre-staged-
# binary skip (sbAlreadyAtCommit landed 2026-05-29; v2026.05.2 is 2026-05-21), so it
# would unconditionally run `make -C cli build` — which fails on the VM (no Go
# toolchain) → BINARY_BUILD_FAILED → rollback. Restarting puts the HEAD binary in
# control, which skips the build (./sb already at target commit). Mirrors the
# stop/start the supervised-unit scenarios already do (3-postswap-watchdog-reconnect).
echo "── restarting upgrade-service unit onto the pre-staged HEAD binary ──"
# vm_restart_unit: dumps journal + status + sb-version before returning non-zero
# so the diagnostics land in the scenario log BEFORE the EXIT trap reaps the VM.
vm_restart_unit "statbus-upgrade@statbus.service"
echo "  ✓ unit active on the HEAD binary"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — REGISTER HEAD as an upgrade candidate (the real post-086 path)
#
# STATBUS-086 (criterion-8 real-path proof): drive the upgrade through the NEW
# operator verbs `./sb upgrade register` + `./sb upgrade schedule` — NOT
# fabricate_scheduled_upgrade_row (which hand-INSERTs a synthetic 'scheduled'
# row, bypassing the real mechanism; fabricate stays for the v2026.05.2-baseline
# kill scenarios that have no daemon-independent scheduling verb — STATBUS-071
# reshapes those). The box is already at HEAD's binary (staged + unit restarted
# above), so it HAS register/schedule. register upserts the candidate
# (state='available') through the SAME upsertCandidate path discovery uses, and
# pokes the service to prepare it: NOTIFY upgrade_check → the daemon's
# verifyArtifacts flips docker_images_status 'building'→'ready' once the four
# per-commit service images are in the registry. That docker_images_status flip
# is what the wait below gates on — for tagged AND untagged HEAD alike.
# (register also sets release_builds_status='ready' for an untagged commit, but
# that field tracks GitHub release artifacts, not the image gate the wait uses.)
#
# INTENTIONALLY NOT quiesced (the unattended-dispatch invariant exception): this
# scenario tests the path where the upgrade SERVICE claims + dispatches the
# scheduled row. The schedule below promotes the candidate → the DB trigger
# NOTIFYs upgrade_apply → the running unit claims + runs executeUpgrade.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── registering HEAD as an upgrade candidate (./sb upgrade register) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $HEAD_LOCAL 2>&1 | tail -20"

echo ""
echo "── waiting for the candidate to reach 'ready' (register → ready) ──"
wait_for_upgrade_candidate_ready "$VM_NAME" "$HEAD_SHA" "$TICK_WAIT_S"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — SCHEDULE the ready candidate (./sb upgrade schedule)
#
# Promotes the row to 'scheduled'; upgrade_notify_daemon_trigger fires NOTIFY
# upgrade_apply; the running (unquiesced) upgrade-service unit claims it and runs
# executeUpgrade → applyPostSwap. This is the genuine
# register→ready→schedule→service-runs→completed real path (criterion-8).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── scheduling the upgrade (./sb upgrade schedule) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $HEAD_LOCAL 2>&1 | tail -20"

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
NRESTARTS_FINAL=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESTART_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$RESTART_DELTA"
if [ "$RESTART_DELTA" -gt 2 ]; then
    echo "✗ NRestarts grew by $RESTART_DELTA during a happy upgrade — unit was unstable" >&2
    exit 1
fi
echo "  ✓ restart counter bounded"

echo ""
echo "PASS: 0-happy-upgrade (supervised unattended path completed cleanly; data intact; unit stable)"
