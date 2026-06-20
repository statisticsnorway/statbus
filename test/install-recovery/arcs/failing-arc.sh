#!/bin/bash
# Arc: failing → failing-fixed  (STATBUS-071 §9 (d)) — the FEW who failed.
#
# The fail → rollback → fix arc + the 3-dim CLEAN-SLATE FINGERPRINT (the
# centerpiece: a failed upgrade must roll back to a BYTE-IDENTICAL pre-upgrade
# state). Driven entirely through the Albania mechanism (register + schedule →
# the upgrade SERVICE runs + rolls back autonomously; NO quiesce, NO ./sb install).
# Shared mechanics live in lib/arc-helpers.sh.
#
# Arc shape (A → B → C):
#   A = base_sha            install fresh, pinned; populate demo data.
#   B = A + V_fail          V_fail is a deterministically FAILING migration
#                           (RAISE EXCEPTION). A→B: executeUpgrade runs migrate up
#                           → fails → recoveryRollback restores the pre-upgrade
#                           snapshot → row='rolled_back'. V_fail is NOT recorded.
#   C = B, V replaced       C edits V IN PLACE to the working migration. Because
#                           V_fail rolled back (unrecorded), V_fixed applies FRESH
#                           on A→C — NOT a re-stamp (no channel-bless needed). The
#                           STATBUS-102 path for "the few who failed": fix ships,
#                           applies cleanly.
#
# CONTRAST with working-arc.sh: (c) = MANY who succeeded (V applied → channel-bless
# re-stamp); (d) = FEW who failed (V rolled back → fresh fix). Together = both
# populations the 072 amend-conveyance must serve.
#
# Inputs (env): BASE_SHA, B_FULL, C_FULL (40-hex), B_BRANCH, C_BRANCH, V_VERSION,
#   SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-failing}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-1200}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${C_FULL:?C_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${C_BRANCH:?C_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: failing → failing-fixed  (fail→rollback→fix + clean-slate)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  C=${C_FULL:0:8}  V=${V_VERSION}"
echo "  SB_ARC_TRUSTED_SIGNER: ${SB_ARC_TRUSTED_SIGNER:+PRESENT (${#SB_ARC_TRUSTED_SIGNER} chars): ${SB_ARC_TRUSTED_SIGNER%% *} ...}${SB_ARC_TRUSTED_SIGNER:-MISSING/EMPTY}"
echo "════════════════════════════════════════════════════════════════"

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# Baseline fingerprint (post-A + demo data) — the rollback must restore THIS
# byte-for-byte. Capture AFTER populate so it reflects the real pre-upgrade state.
echo "── capturing baseline clean-slate fingerprint (post-A) ──"
BASELINE_FP=$(capture_db_fingerprint baseline)
echo "  baseline fingerprint: $BASELINE_FP"

# ── B: V_fail → executeUpgrade fails → autonomous rollback → 'rolled_back' ──
arc_to "$B_FULL" "$B_BRANCH" "B (V_fail rolls back)" "rolled_back"
echo "── assert clean rollback to A (the centerpiece) ──"
assert_health_passes "$VM_NAME"
MROWS_B=$(migration_row_count)
[ "$MROWS_B" = "0" ] || { echo "✗ V_fail left a ledger row (count=$MROWS_B, want 0) — rollback did not unrecord it" >&2; exit 1; }
echo "  ✓ V_fail not recorded in db.migration (rolled back)"
assert_fingerprint_matches "post-rollback == post-A" "$BASELINE_FP" baseline
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"

# ── C: V replaced with the working migration → applies FRESH (no re-stamp) ──
arc_to "$C_FULL" "$C_BRANCH" "C (V_fixed applies fresh)" "completed"
echo "── assert the fix applied cleanly ──"
RC=$(fixture_row_count)
[ "$RC" = "1" ] || { echo "✗ V_fixed not applied: public.upgrade_arc_fixture count=$RC (want 1)" >&2; exit 1; }
MROWS_C=$(migration_row_count)
[ "$MROWS_C" = "1" ] || { echo "✗ V recorded ${MROWS_C} times after C (want exactly 1 — fresh apply)" >&2; exit 1; }
H_C=$(migration_content_hash)
[ -n "$H_C" ] && [ "$H_C" != "ERR" ] || { echo "✗ no content_hash for V=$V_VERSION after C" >&2; exit 1; }
echo "  ✓ V_fixed applied fresh (fixture present); recorded once; H_C=${H_C:0:16}…"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: failing → failing-fixed (A→B failed + rolled back to a byte-identical clean slate; A→C applied the fix fresh; data intact; healthy)"
