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
#   quiescence pre-step before the migrate phase. With the fix, the
#   upgrade completes in bounded time regardless of what the worker is
#   doing. Without it, the migration would hang forever waiting for
#   AccessExclusiveLock — the wedge tcc had to manually break.
#
# STATUS (architect assessment, STATBUS-071 comment, 2026-07-14): the R1
# fix has SHIPPED on both paths this scenario's header used to say did not
# exist — the "LIKELY RED" / "no fix exists" premise here was written at
# 1f077e545 and is now stale:
#   - INSTALL path: the R1 quiesce window is wired into the step loop
#     (cli/cmd/install.go:633-680) — compose.QuiesceClients stops
#     worker/app/rest before the Seed/Migrations steps whenever those
#     steps actually need to run, HARD-FAILS if the quiesce itself fails
#     ("must not proceed with DDL on live services"), and ResumeClients
#     restarts exactly the stopped set once the window closes
#     (compose.go:126/:158); db/proxy stay up throughout.
#   - UPGRADE path: Step 3 stops app/worker/rest before backup/swap
#     (service.go:5190-5193); the delta then runs on the new binary with
#     clients still down, services returning only after migrate + health.
# This scenario is therefore no longer a documented-but-unrunnable RED
# reproducer — it is the REGRESSION NET for the shipped fix. The trigger
# direction that matters is GREEN and deterministic: with the quiesce in
# place, completion does not depend on winning any lock race against the
# worker — the continuous workload below exists to PROVE the quiesce beats
# a genuinely-busy worker, not to reproduce the old wedge (which would
# require un-fixing the product; that history stays in the forensics doc,
# not re-proved here).
#
# Pass criteria (unchanged from before the fix — this scenario's own
# activation condition, "runs the moment the R1 fix is ready", is now met):
#   - install reaches a terminal state within INSTALL_BUDGET_S
#     (15 min default) — completed via service-quiescence path
#   - assert_demo_data_present passes (data intact)
#   - assert_demo_data_counts_match_snapshot passes (migrate-forward
#     MUST NOT alter user-data row counts)
#   - assert_systemd_restart_counter_bounded ≤ 2 (no restart loop
#     pathology while waiting for lock)
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (default v2026.07.0-rc.05 — a recent
#      baseline with a real migration delta to HEAD, re-pinned from the
#      stale v2026.05.2 default per the architect's 2026-07-14 assessment).
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
#      apply, the R1 quiesce stops the worker BEFORE any DDL runs, so
#      there is no AccessExclusiveLock contention to resolve in the
#      first place — the workload is a live demonstration that the fix
#      does not depend on lock-race timing.
#   5. Time-bound the install. Reaching a terminal state within
#      INSTALL_BUDGET_S is the expected, principled outcome now that the
#      fix has shipped; hanging past the budget would be a genuine
#      regression of R1, not an expected finding.
#
# Hetzner-runnability:
#   RUNS NOW. The prior header's "committed but does not run until the
#   fix lands" note is obsolete — the fix landed, this is exactly the
#   bounded VM run the architect's assessment calls for to flip the
#   coverage map's last [ASSESS] row to [PROVEN].
#
# Usage:
#   INSTALL_VERSION=v2026.07.0-rc.05 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-worker-ddl-deadlock.sh \
#     statbus-recovery-3-postswap-worker-ddl-deadlock

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-worker-ddl-deadlock}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.07.0-rc.05}"
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
# upgrade applies migrations, the R1 quiesce (Step 3, service.go:5190-5193)
# stops app/worker/rest BEFORE the delta runs — any DDL on a table the
# worker would otherwise be reading (statistical_history,
# statistical_history_facet, statistical_unit, etc.) never contends for
# AccessExclusiveLock in the first place, because the worker holding
# AccessShareLock is stopped before the migration even starts. The
# workload's job is to prove exactly that: it stays "genuinely busy" right
# up to the trigger, and the quiesce still wins deterministically.
#
# Time-bound the install to INSTALL_BUDGET_S. If install hangs past
# that, the trap kills the workload + cleans up the VM; the
# assertions below interpret the install's exit code.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── fabricating scheduled public.upgrade row for HEAD ──"
# Seed a scheduled upgrade row so ./sb install routes through
# ExecuteUpgradeInline -> executeUpgrade, whose Step 3 (service.go:5190-5193)
# stops app/worker/rest before the backup/swap — the worker is quiesced
# BEFORE the delta migration ever runs in applyNewSbUpgrading — rather than
# detecting nothing-scheduled and running the no-op step-table path.
# Uses HEAD_SHA (the variable this file defines at line ~103).
# Quiesce first: the running upgrade service (NOTIFY listener + poll tick)
# would otherwise claim this scheduled row before `./sb install` reaches it
# → StateNothingScheduled → no-op step-table → the DDL contention never
# happens, so R1 ("service quiescence before DDL") could never validate here.
# Fabricate-claim race invariant (see quiesce_upgrade_service in wedge-helpers).
quiesce_upgrade_service "$VM_NAME"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_SHA"

echo ""
echo "── triggering install at HEAD with worker still holding locks ──"

# Suppress set -e around the install: kept non-fatal on a non-zero exit
# rather than asserting inline, so the R1 check below can distinguish a
# budget timeout (124 — the regression this scenario now guards against)
# from any other terminal exit code, and report which one occurred.
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
# Hard constraint: the install MUST NOT hang indefinitely. With the R1
# quiesce shipped, completing within INSTALL_BUDGET_S is the expected,
# principled outcome (regression net) — exit 124 from `timeout(1)` would
# mean the install was still running when the budget expired, i.e. the
# quiesce did not prevent the old wedge. That is a genuine regression of
# R1, not an expected finding.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── R1 deadlock-bounded check (load-bearing) ──"

if [ "$INSTALL_EXIT" = "124" ]; then
    # timeout(1) sends SIGTERM after the budget elapses. Exit 124 = the
    # install was still running when the budget expired — the R1 quiesce
    # did not prevent the wedge tcc originally surfaced. A regression, not
    # an expected outcome now that the fix has shipped.
    echo "  ✗ install did NOT reach a terminal state within ${INSTALL_BUDGET_S}s — R1 REGRESSION (the shipped quiesce did not prevent the wedge)"
    echo "    Check cli/cmd/install.go:633-680 (compose.QuiesceClients) and service.go:5190-5193 (Step 3 client stop)."
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
