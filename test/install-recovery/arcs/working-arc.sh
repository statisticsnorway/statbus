#!/bin/bash
# Arc: working → working-fixed  (STATBUS-071 §9 (c)) — the MANY who succeeded.
#
# The STATBUS-072 re-stamp, proven end-to-end on a real VM via the Albania
# mechanism (register + schedule → the upgrade SERVICE runs it autonomously; NO
# quiesce, NO ./sb install). Shared mechanics live in lib/arc-helpers.sh.
#
# Arc shape (A → B → C, all post-086 commits):
#   A = base_sha            install fresh, pinned (install_statbus_at_sha).
#   B = A + V               V is a genuine migration that SUCCEEDS. A→B applies it
#                           and records it in db.migration with content_hash H_B.
#   C = B with V amended    C edits V IN PLACE (§7 Option-1: bytes change → hash
#                           H_C ≠ H_B, RESULT identical) AND declares V in
#                           migrations/amendments.tsv. B→C: the eager content-hash
#                           check sees H_C ≠ H_B, finds V in the amendments set →
#                           RE-STAMPS db.migration.content_hash to H_C (does NOT
#                           hard-fail, does NOT re-run V). The real 072 path for
#                           "the many who already succeeded at V".
#
# Inputs (env): BASE_SHA, B_FULL, C_FULL (40-hex), B_BRANCH, C_BRANCH, V_VERSION,
#   SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-working}"
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
echo "  Arc: working → working-fixed  (re-stamp / Albania autonomous)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  C=${C_FULL:0:8}  V=${V_VERSION}"
echo "  SB_ARC_TRUSTED_SIGNER: ${SB_ARC_TRUSTED_SIGNER:+PRESENT (${#SB_ARC_TRUSTED_SIGNER} chars): ${SB_ARC_TRUSTED_SIGNER%% *} ...}${SB_ARC_TRUSTED_SIGNER:-MISSING/EMPTY}"
echo "════════════════════════════════════════════════════════════════"

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ── B: V applies (the many-who-succeed precondition) ──
arc_to "$B_FULL" "$B_BRANCH" "B (V applies)" "completed"
echo "── assert V applied + recorded ──"
RC=$(fixture_row_count)
[ "$RC" = "1" ] || { echo "✗ V not applied: public.upgrade_arc_fixture count=$RC (want 1)" >&2; exit 1; }
H_B=$(migration_content_hash)
[ -n "$H_B" ] && [ "$H_B" != "ERR" ] || { echo "✗ no content_hash for V=$V_VERSION after B" >&2; exit 1; }
echo "  ✓ V applied (fixture row present); H_B=${H_B:0:16}…"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"

# ── C: V amended in place + declared in amendments.tsv → RE-STAMP (no re-run) ──
arc_to "$C_FULL" "$C_BRANCH" "C (V amended → re-stamp)" "completed"
echo "── assert re-stamp (content_hash changed; V neither re-run nor duplicated) ──"
H_C=$(migration_content_hash)
[ -n "$H_C" ] && [ "$H_C" != "ERR" ] || { echo "✗ no content_hash for V=$V_VERSION after C" >&2; exit 1; }
if [ "$H_C" = "$H_B" ]; then
    echo "✗ content_hash UNCHANGED after C ($H_C) — re-stamp did NOT fire" >&2
    exit 1
fi
echo "  ✓ content_hash re-stamped: H_B=${H_B:0:16}… → H_C=${H_C:0:16}…"
MROWS=$(migration_row_count)
[ "$MROWS" = "1" ] || { echo "✗ V duplicated/lost in db.migration: count=$MROWS (want 1 — re-stamp updates in place)" >&2; exit 1; }
RC2=$(fixture_row_count)
[ "$RC2" = "1" ] || { echo "✗ V's RESULT changed after amend: fixture count=$RC2 (want 1 — amend is result-preserving)" >&2; exit 1; }
echo "  ✓ V's effect preserved (fixture intact); exactly one ledger row (re-stamped in place)"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: working → working-fixed (A→B applied V; B→C re-stamped content_hash autonomously; data intact; healthy)"
