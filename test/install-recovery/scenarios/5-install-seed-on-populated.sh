#!/bin/bash
# Scenario: 5-install-seed-on-populated  (C17 / R5 — DATA LOSS GRADE)
#
# Class:                 seed-restore-runs-on-populated-database-destroying-data
# Forensics tag:         R5 (architectural)
# Source forensics:      tmp/install-state-machine-forensics.md (jo + tcc near-miss)
#
# Expected principled behavior:
#   Install MUST NOT execute the destructive seed-restore step against a
#   database that already holds user data. When the install state machine
#   reaches state nothing-scheduled with a migration-tail mismatch (disk
#   migrations newer than db.migration's max), it must classify DB content
#   (populated vs empty) before dispatching the seed step. Populated →
#   route to migrate-forward only. Empty → seed-restore is appropriate.
#
# Known status on current code (commit 99ae765b2 / engineer/upgrade-recovery-validation):
#   LIKELY RED. checkSeedRestored at cli/cmd/install.go:1274 guards on
#   checkMigrationsDone returning false (i.e. HasPending == true). When the
#   harness drives the VM to (populated DB + new migrations on disk that
#   the DB has not yet applied), HasPending returns true, checkMigrationsDone
#   returns false, checkSeedRestored returns false, and the step-table
#   dispatches runSeedRestore. runSeedRestore fetches origin/db-seed and
#   runs pg_restore, silently destroying the existing rows. The architectural
#   fix (DB-content classifier before seed dispatch) is a separate arc; this
#   scenario surfaces the bug empirically when run.
#
# Pass criteria once the fix lands:
#   - assert_demo_data_present passes (load-bearing R5 catastrophic-loss detector)
#   - install either completes cleanly via migrate-forward OR refuses with a
#     clear diagnostic mentioning the populated-DB condition
#   - assert_demo_data_counts_match_snapshot passes (no data drift —
#     migrate-forward MUST NOT alter user-data row counts)
#
# Trigger logic (Option 1 from the C17 spec):
#   1. Install at INSTALL_VERSION (older release with fewer migrations than
#      HEAD on the harness's local checkout). v2026.05.2 has ~3 fewer
#      migration pairs than HEAD, enough to make HasPending return true after
#      we switch the binary + git tree to HEAD.
#   2. Populate the DB with demo data via populate_with_demo_data.
#   3. Re-run install_statbus_in_vm with NO version — this uses the local
#      HEAD's binary + git checkout, putting newer migration files on disk
#      while the database stays at INSTALL_VERSION's migration tail. The
#      install state machine probes nothing-scheduled, the step-table runs
#      Seed, and (on buggy code) destroys the populated data.
#
# Why this trigger rather than the alternative (manipulate db.migration
# directly, force the seed-trigger condition synthetically): Option 1 mirrors
# the real-world failure mode — operator runs ./sb install on a populated
# host after pulling a newer git tree. tcc's near-miss followed exactly
# this shape. Option 2 (synthetic state surgery) would test the post-classify
# code path but not the actual production path.
#
# Hetzner-runnability: this scenario is COMMITTED but DOES NOT RUN on Hetzner
# until the architectural fix lands. Running it today would burn a Hetzner
# VM to confirm the bug — which we already know exists from the tcc forensics.
# The scenario file lives on the branch as documentation + a regression net
# that activates the moment the fix is ready.
#
# Usage (deferred until the architectural fix lands):
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/5-install-seed-on-populated.sh \
#     statbus-recovery-5-install-seed-on-populated

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-seed-on-populated}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 5-install-seed-on-populated  (C17 / R5 — DATA LOSS GRADE)"
echo "  Initial release: $INSTALL_VERSION → second install: local HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"
echo "  INSTALL_VERSION: $INSTALL_VERSION"

# ─────────────────────────────────────────────────────────────────────────
# Phase 1 — bootstrap VM + initial install at older release
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

# Sanity check: data IS present before the trigger. If not, the scenario's
# precondition itself is broken — fail loudly before the destructive step.
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — trigger seed-on-populated condition
#
# Switch the VM's sb binary + git checkout to HEAD without touching the
# database. The new binary has migration files on disk that the database
# has not applied (HEAD is several migrations ahead of $INSTALL_VERSION),
# so HasPending returns true and the step-table's Seed guard
# (checkSeedRestored) routes through to runSeedRestore against the
# populated DB.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── triggering second install at HEAD (forces seed-trigger state) ──"

# install_statbus_in_vm with no version uses the local repo's HEAD: scp's
# the local sb binary, fetches + checks out HEAD inside the VM, then runs
# ./sb install. This is exactly the operator-shape that produced tcc's
# near-miss — pull the newer tree, re-run install on a populated host.
#
# We deliberately DO NOT bail on the install's exit code. The install
# may exit 0 (after destroying data, on buggy code) or exit non-zero
# (after refusing, on fixed code). Either way the load-bearing
# assertion is "data is still present afterwards" — which we check
# below regardless of exit status.
set +e
install_statbus_in_vm "$VM_NAME"
INSTALL_EXIT=$?
set -e
echo "  second install exited: $INSTALL_EXIT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — assertions (load-bearing R5 catastrophic-loss detector)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── R5 catastrophic-loss check (load-bearing) ──"

# THE LOAD-BEARING ASSERTION. If this fails, R5 is confirmed on current
# code — the install state machine destroyed user data. The fix is the
# DB-content classifier (Phase 2 CLASSIFY per the forensics doc).
assert_demo_data_present "$VM_NAME"

# Stricter: counts unchanged. migrate-forward MUST NOT alter user-data row
# counts. If counts differ, even partial loss has occurred (or the install
# applied a migration that mutates user data — both are signals to
# investigate).
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# Install must reach SOME terminal state — not hang. We don't gate on
# exit code (both clean-completion and clean-refusal are acceptable per
# the principled behaviour), but the system must be queryable + healthy.
assert_health_passes "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — coherence assertions
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── coherence checks ──"

# Whatever path the install took, the flag file must not be lingering.
assert_flag_file_absent "$VM_NAME"

# No orphan pre-upgrade-* backup dirs (Layer 3 hygiene).
assert_no_orphan_backup "$VM_NAME"

# systemd restart counter bounded — the upgrade-service unit must not be
# in a restart-loop pathology after this install (Race B sister of the
# data-loss bug, both surface as "things going wrong silently").
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@statbus.service" 2

echo ""
echo "PASS: 5-install-seed-on-populated (data survived install against populated DB)"
