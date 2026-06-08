#!/bin/bash
# Scenario: 3-postswap-worker-ddl-deadlock  (C13 / R1 — most-damaging architectural)
#
# Class:                 migration-deadlocks-with-running-worker-holding-table-lock
# Forensics tag:         R1 (architectural)
# Source forensics:      tmp/install-state-machine-forensics.md (jo + tcc near-miss)
#
# Expected principled behavior:
#   The install state machine MUST NOT allow a worker holding
#   AccessShareLock on a statistical-history table to block an upgrade-
#   time DDL migration indefinitely. The fix per forensics is a service-
#   quiescence pre-step (narrow: pause the worker queue; full: 6-phase
#   QUIESCE) before the migrate phase. With the fix, the upgrade
#   completes in bounded time. Without the fix, the migration hangs
#   forever waiting for AccessExclusiveLock — the wedge tcc had to
#   manually break.
#
# Known status on current code (commit 1f077e545 / engineer/upgrade-recovery-validation):
#   LIKELY RED. There is no quiesce-services-before-DDL step in the
#   install state machine. When the worker holds AccessShareLock on
#   statistical_history (or related tables) and a migration tries to
#   take AccessExclusiveLock on the same target, Postgres lock manager
#   parks the migration indefinitely. systemd's TimeoutStartSec
#   eventually fires (Layer 1 SIGTERM, ~Race B), but that's the
#   wrong remediation — Layer 1 cleanup happens AFTER damage, where
#   service quiescence prevents damage from starting. The
#   architectural fix (R1: quiesce services before DDL) is a separate
#   arc; this scenario surfaces the bug empirically when run.
#
# Pass criteria once the fix lands:
#   - install reaches a terminal state within INSTALL_BUDGET_S
#     (15 min default) — completed via service-quiescence path
#   - assert_demo_data_present passes (data intact)
#   - assert_demo_data_counts_match_snapshot passes (migrate-forward
#     MUST NOT alter user-data row counts)
#   - assert_systemd_restart_counter_bounded ≤ 2 (no restart loop
#     pathology while waiting for lock)
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.05.2 — same baseline
#      as scenario 5-install-seed-on-populated; provides a migration delta to apply).
#   2. Populate via populate_with_demo_data.
#   3. Start continuous worker workload via
#      start_continuous_worker_workload — the helper enqueues
#      statistical_history_reduce tasks every 2s, which the worker
#      picks up and runs. Each reduce holds AccessShareLock on
#      statistical_history-related tables for seconds. The workload
#      duration is extended to WORKLOAD_DURATION_S (900s default —
#      longer than the install's normal budget so the worker is
#      reliably busy across the entire upgrade window).
#   4. Run install_statbus_in_vm with NO version — uses local HEAD,
#      which has migrations newer than $INSTALL_VERSION. As migrations
#      apply, any DDL on a worker-touched table contends for
#      AccessExclusiveLock.
#   5. Time-bound the install. If it returns within INSTALL_BUDGET_S
#      with a terminal state, the system is principled (current code
#      has no fix — this would be a green outcome only after the
#      architectural fix lands). If install hangs past the budget,
#      the wedge is observed — RED state surfaced.
#
# Hetzner-runnability:
#   COMMITTED but does NOT run on Hetzner until the architectural
#   fix lands. Running today would burn a VM to confirm a known
#   wedge — and the wedge itself ties up the VM for the full budget
#   (15+ min of "hanging migration") before the trap cleans up.
#   The scenario file lives on the branch as documentation + a
#   regression net that activates the moment the R1 fix is ready.
#
# Usage (deferred until the architectural fix lands):
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-worker-ddl-deadlock.sh \
#     statbus-recovery-3-postswap-worker-ddl-deadlock

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-worker-ddl-deadlock}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"           # 15 min hard cap
WORKLOAD_DURATION_S="${WORKLOAD_DURATION_S:-900}"     # match install budget

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

# Cleanup trap: stop the continuous workload (even on failure) before
# the VM is deleted, so the VM doesn't hold the workload's tmux session
# open during cleanup_vm. cleanup_vm runs unconditionally after.
trap '
    rc=$?
    stop_continuous_worker_workload "$VM_NAME" 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-worker-ddl-deadlock  (C13 / R1 — most-damaging)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "  Install budget: ${INSTALL_BUDGET_S}s; workload duration: ${WORKLOAD_DURATION_S}s"
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
# Phase 2 — populate with demo data
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"

DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — start continuous worker workload
#
# The harness's start_continuous_worker_workload enqueues
# statistical_history_reduce tasks every WORKLOAD_INSERT_INTERVAL_S
# seconds (default 2s) into worker.tasks. The worker picks them up via
# its analytics queue and runs the reduce — each takes seconds and
# holds AccessShareLock on statistical_history-related tables for the
# duration. Extending the workload to WORKLOAD_DURATION_S ensures the
# worker is busy across the entire upgrade window.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── starting continuous worker workload (duration=${WORKLOAD_DURATION_S}s) ──"
start_continuous_worker_workload "$VM_NAME" "$WORKLOAD_DURATION_S"

# Give the worker a few seconds to actually pick up tasks and acquire
# locks before triggering the migration. Without this, the install can
# race ahead of the worker and miss the lock contention window.
sleep 10

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — trigger upgrade with worker holding locks
#
# The install_statbus_in_vm with no version uses local HEAD. As the
# upgrade applies migrations, any DDL on a table the worker is reading
# (statistical_history, statistical_history_facet, statistical_unit,
# etc.) tries to take AccessExclusiveLock and blocks behind the
# worker's AccessShareLock. On current code with no quiesce-services-
# before-DDL pre-step, the migration hangs until the worker's task
# completes (per-task) or until the workload duration expires (whole
# workload).
#
# Time-bound the install to INSTALL_BUDGET_S. If install hangs past
# that, the trap kills the workload + cleans up the VM; the
# assertions below interpret the install's exit code.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── fabricating scheduled public.upgrade row for HEAD ──"
# Seed a scheduled upgrade row so ./sb install routes through
# executeUpgradeInline -> applyPostSwap (where the DDL migration contends
# with the worker's AccessShareLock), rather than detecting nothing-scheduled
# and running the no-op step-table path.  This scenario is still KNOWN RED
# until the R1 architectural fix (service quiescence before DDL) lands.
# Uses HEAD_SHA (the variable this file defines at line ~103).
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_SHA"

echo ""
echo "── triggering install at HEAD with worker still holding locks ──"

# Suppress set -e around the install: the install MAY exit non-zero
# (e.g., systemd's TimeoutStartSec triggers SIGTERM after the
# migration hangs, or the install detects the deadlock and refuses).
# Both are acceptable terminal states per the principled-behavior
# spec; the load-bearing check is "does the system reach a terminal
# state within budget, and is the data intact afterwards?"
set +e
timeout "${INSTALL_BUDGET_S}s" \
    bash -c "install_statbus_in_vm \"$VM_NAME\"" \
    < /dev/null
INSTALL_EXIT=$?
set -e
echo "  install exited: $INSTALL_EXIT (124 = budget timeout)"

# Stop the workload now that the install attempt is over. The trap
# would do it anyway, but stopping early frees the worker for any
# post-install probes the assertions need.
stop_continuous_worker_workload "$VM_NAME" || true

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — assertions
#
# Hard constraint: the install MUST NOT hang indefinitely. Either it
# completes within INSTALL_BUDGET_S (current code probably won't —
# the wedge is the RED state) or it returns with a clean exit code
# (the principled behaviour we are testing for). Exit 124 from
# `timeout(1)` means the install was killed at the budget — that's
# the wedge.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── R1 deadlock-bounded check (load-bearing) ──"

if [ "$INSTALL_EXIT" = "124" ]; then
    # timeout(1) sends SIGTERM after the budget elapses. Exit 124 = the
    # install was still running when the budget expired. This IS the
    # wedge tcc surfaced — the current code does not bound the
    # deadlock, and the harness had to forcibly kill the install.
    echo "  ✗ install did NOT reach a terminal state within ${INSTALL_BUDGET_S}s — R1 wedge confirmed"
    echo "    The architectural fix (service quiescence before DDL) is required."
    exit 1
fi

# Install returned within budget — check that the terminal state is
# coherent and data survived.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_health_passes "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — coherence checks
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── coherence checks ──"

assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"

# Restart counter bounded — the upgrade-service unit must not be in a
# restart-loop pathology after this install (the wedge could
# plausibly trip systemd's StartLimitBurst if the migration is killed
# + retried repeatedly).
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 3-postswap-worker-ddl-deadlock (install survived worker contention, data intact)"
