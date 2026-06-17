#!/bin/bash
# Scenario: 2-preswap-checkout-kill-legacy  (genuine v2026.05.2-binary production path)
#
# Class:                 preswap-checkout-kill (synthetic wedge, legacy binary shape)
# Class kind:            Synthetic-wedge (no inject site — genuine pre-fix binary behavior)
# Source forensics:      tmp/install-state-machine-forensics.md (STATBUS-026)
#                        STATBUS-060: deferred-checkout fix
#                        STATBUS-059: preswap-checkout-forward-fix
#
# Purpose:
#   Proves that HEAD's recovery code handles the pre-STATBUS-060 crash state —
#   the wedge that v2026.05.2's executeUpgrade left behind when killed AFTER
#   `git checkout <target>` but BEFORE the binary swap. This is NOT a
#   scenario that can be injected with inject.KillHere (the inject framework
#   exists only in HEAD; v2026.05.2 pre-dates it). Instead, write_preswap_wedge
#   directly synthesises the on-disk crash state: flag=PreSwap, working tree
#   at TARGET commit, binary still v2026.05.2, backup dir created (managed
#   name), services stopped.
#
# Key difference from 2-preswap-checkout-kill (HEAD scenario):
#   HEAD (post-STATBUS-060): executeUpgrade no longer does `git checkout`
#     before the binary swap → working tree stays at OLD_COMMIT → RED proves
#     "no pre-swap checkout happened".
#   HERE (legacy v2026.05.2 shape): executeUpgrade DID do `git checkout target`
#     before the kill → working tree IS at HEAD_LOCAL → RED proves "v2026.05.2
#     advanced the working tree into the target-compose era before dying".
#
# Expected principled behavior:
#   HEAD's recovery (real install.sh --channel edge, STATBUS-060 operator path)
#   handles the pre-fix wedge:
#     runCrashRecovery: git checkout flag.CommitSHA (no-op — already there),
#       config generate, StartDBForRecovery, migrate up, RecoverFromFlag.
#     recoverFromFlag PreSwap branch → recoveryRollback → rollback():
#       restoreGitState restores to the pinned pre-upgrade branch (pinned to source
#       CommitSHA; STATBUS-077 made the branch the single recovery source — the
#       from_commit_sha column was removed);
#       from_commit_version "2026.05.2" is stored for display only, not used for restore.
#       restoreDatabase is no-op (flag.BackupPath=""), docker compose up.
#   Convergence: working tree at source CommitSHA, row='failed'/'rolled_back',
#   data intact, flag absent, no orphan backups.
#
# Trigger logic:
#   1. Install at INSTALL_VERSION (v2026.05.2). Verify health.
#   2. Populate via populate_with_demo_data. Snapshot data counts.
#   3. Capture OLD_COMMIT (post-install working-tree HEAD).
#   4. Capture SB_VERSION_BEFORE (v2026.05.2 binary).
#   5. fabricate_scheduled_upgrade_row (public.upgrade row in 'scheduled').
#   6. write_preswap_wedge: transitions row to 'in_progress', stops services,
#      creates pre-upgrade-active dir, pins pre-upgrade branch to OLD_COMMIT,
#      `git fetch + git checkout HEAD_LOCAL` (old behavior), writes flag JSON.
#   7. Verify RED: flag present; working tree IS at HEAD_LOCAL (v2026.05.2
#      DID the checkout — the pre-fix bug); binary still v2026.05.2.
#   8. Recovery via real install.sh --channel edge (STATBUS-060 operator path).
#   9. Assert convergence: row='failed'/'rolled_back'; working tree BACK at
#      OLD_COMMIT; data intact; flag absent; no orphan backups; health passes.
#
# Hetzner-runnability:
#   READY. No inject site needed; write_preswap_wedge synthesises the state
#   directly. The scenario validates that HEAD's recovery code is backward-
#   compatible with the pre-STATBUS-060 crash shape from v2026.05.2.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/2-preswap-checkout-kill-legacy.sh \
#     statbus-recovery-2-preswap-checkout-kill-legacy

set -euo pipefail

VM_NAME="${1:-statbus-recovery-2-preswap-checkout-kill-legacy}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 2-preswap-checkout-kill-legacy"
echo "            (genuine v2026.05.2 preswap crash shape + HEAD recovery)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD-local: $HEAD_LOCAL ($(echo "$HEAD_LOCAL" | cut -c1-8))"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# Capture the working-tree commit AFTER the initial install — this is OLD_COMMIT,
# the commit that restoreGitState must return us to after recovery.
OLD_COMMIT=$(VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d '\r' || echo "")
if [ -z "$OLD_COMMIT" ]; then
    echo "✗ could not read working-tree HEAD post-initial-install" >&2
    exit 1
fi
echo "  pre-wedge working-tree HEAD: $OLD_COMMIT ($(echo "$OLD_COMMIT" | cut -c1-8))"

# Capture the v2026.05.2 binary version BEFORE any upload — this proves the wedge
# uses the genuine INSTALL_VERSION binary, not HEAD's.
SB_VERSION_BEFORE=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
echo "  INSTALL_VERSION binary: $SB_VERSION_BEFORE"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-wedge data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — synthesise the v2026.05.2 preswap crash state
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── synthesising v2026.05.2 preswap crash state ──"

# Seed a scheduled public.upgrade row for HEAD. write_preswap_wedge will
# transition it to in_progress (as executeUpgrade would have done), stop the
# DB, perform the git checkout (old behavior), and write the flag file.
# DB must be up at this point — fabricate_scheduled_upgrade_row opens psql.
# Quiesce first so the running upgrade service can't claim the scheduled row
# in the window before write_preswap_wedge transitions it to in_progress
# (fabricate-claim race invariant; see quiesce_upgrade_service in wedge-helpers).
quiesce_upgrade_service "$VM_NAME"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

# write_preswap_wedge requires the DB to still be up (it transitions the row
# to in_progress before stopping docker). Pass the release v2026.05.2's d.version
# string so from_commit_version is faithful to what v2026.05.2's executeUpgrade
# stored (service.go:1308 / service.go:3498 write d.version verbatim — v-stripped).
# The release v2026.05.2 uses d.version = "2026.05.2" (no v-prefix); cobra's
# --version output is "sb version 2026.05.2 (commit <sha>)", so awk '{print $3}'
# extracts field 3 — the bare "2026.05.2" — matching d.version exactly.
# from_commit_version "2026.05.2" is stored for display only; recovery restores via the
# pinned pre-upgrade branch (STATBUS-077 removed the from_commit_sha column).
SB_VERSION_FROM=$(echo "$SB_VERSION_BEFORE" | awk '{print $3}')
write_preswap_wedge "$VM_NAME" "$HEAD_LOCAL" "$SB_VERSION_FROM"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — verify RED state (pre-fix crash shape)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── verifying pre-fix RED state ──"

VM_EXEC bash -c "ls -la ~/statbus/tmp/upgrade-in-progress.json" || {
    echo "✗ expected flag file present after write_preswap_wedge" >&2
    exit 1
}
# NOTE: do NOT assert public.upgrade.state='in_progress' here — docker is stopped
# (write_preswap_wedge step 2). Row-state convergence belongs in Phase 6.

# Load-bearing RED: v2026.05.2's executeUpgrade DID do `git checkout <target>`
# before the kill (the pre-STATBUS-060 bug). The working tree IS at HEAD_LOCAL.
# This is the failure mode STATBUS-060 closed: the old binary materialised the
# target's docker-compose files (including REST_ADMIN_BIND_ADDRESS) before dying,
# preventing EnsureDBUp on the next recovery boot.
WT_COMMIT_DURING=$(VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d '\r' || echo "")
if [ "$WT_COMMIT_DURING" != "$HEAD_LOCAL" ]; then
    echo "✗ write_preswap_wedge did not advance the working tree to HEAD_LOCAL" >&2
    echo "  expected: $HEAD_LOCAL" >&2
    echo "  got:      $WT_COMMIT_DURING" >&2
    echo "  The wedge must simulate v2026.05.2's pre-fix checkout behavior." >&2
    exit 1
fi
echo "  ✓ working tree IS at HEAD_LOCAL ($(echo "$HEAD_LOCAL" | cut -c1-8)) — pre-fix checkout happened"
echo "    (STATBUS-060 removed this checkout; on HEAD the working tree stays at OLD_COMMIT)"

# Binary still v2026.05.2 — binary swap never reached.
SB_VERSION_DURING=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null | head -1" | tr -d '\r' || echo "")
if [ "$SB_VERSION_DURING" != "$SB_VERSION_BEFORE" ]; then
    echo "✗ binary changed during wedge setup ($SB_VERSION_BEFORE → $SB_VERSION_DURING)" >&2
    exit 1
fi
echo "  ✓ binary still v2026.05.2 ($SB_VERSION_BEFORE) — no swap in preswap window"
echo "  ✓ RED confirmed: flag PreSwap, working tree at target (old checkout), binary unswapped"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — recovery via HEAD binary (install_statbus_in_vm without version)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── recovery via real install.sh --channel edge (STATBUS-060 operator path) ──"
# STATBUS-060: install_statbus_in_vm (no version) now runs the real install.sh
# --channel edge (operator recovery entrypoint). install.sh procures HEAD's sb
# binary via docker image (or build fallback), then calls ./sb install which
# detects the PreSwap flag and handles the pre-fix crash state:
#   git checkout flag.CommitSHA (no-op — WT already at HEAD_LOCAL),
#   config generate, StartDBForRecovery, migrate up,
#   RecoverFromFlag → PreSwap branch → recoveryRollback → rollback() →
#     restoreGitState: restores to the pinned pre-upgrade branch (pinned to source
#                      CommitSHA; STATBUS-077 — recovery is branch-based, the
#                      from_commit_sha column was removed),
#     restoreDatabase (no-op, flag.BackupPath=""),
#     docker compose up.
# install.sh exits 0 for both success and rollback (rc=75 → install.sh banner + exit 0).
# Catastrophic failures are non-zero and abort via set -e. Outcome: upgrade row state.
install_statbus_in_vm "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — convergence assertions
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

# Row must be in a principled ABORT terminal state (not 'completed' — the
# upgrade was killed before the binary-swap commit boundary).
FINAL_STATE=$(VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  final upgrade row state: $FINAL_STATE"
case "$FINAL_STATE" in
    failed|rolled_back)
        echo "  ✓ row reached a principled ABORT terminal state ($FINAL_STATE)"
        ;;
    completed)
        echo "✗ row state='completed' is NOT valid for a preswap kill — upgrade was never committed at the binary-swap boundary" >&2
        exit 1
        ;;
    *)
        echo "✗ unexpected terminal state: $FINAL_STATE" >&2
        exit 1
        ;;
esac

# Error column must name the PreSwap-guard rollback reason — confirms this went
# through recoverFromFlag's PreSwap branch (ErrInstallPreconditionFailed).
assert_upgrade_row_error_matches "$VM_NAME" "INSTALL_PRECONDITION_FAILED"

# Load-bearing GREEN: restoreGitState restored via the pinned pre-upgrade branch
# (pinned to source CommitSHA by write_preswap_wedge step 4; STATBUS-077 — recovery
# is branch-based). from_commit_version "2026.05.2" is display-only.
# Working tree returned to source CommitSHA despite the release v2026.05.2's pre-fix checkout.
WT_COMMIT_AFTER=$(VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d '\r' || echo "")
if [ "$WT_COMMIT_AFTER" != "$OLD_COMMIT" ]; then
    echo "✗ working tree not restored to source CommitSHA $OLD_COMMIT (got $WT_COMMIT_AFTER)" >&2
    echo "  restoreGitState (pre-upgrade branch restore) did not work" >&2
    exit 1
fi
echo "  ✓ working tree at source CommitSHA $(echo "$OLD_COMMIT" | cut -c1-8)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 2-preswap-checkout-kill-legacy"
echo "      (HEAD recovery handled release v2026.05.2 preswap crash shape;"
echo "       working tree at source CommitSHA, release unchanged, data intact)"
