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
#   C = B with V amended    C edits V IN PLACE (bytes change → hash H_C ≠ H_B,
#                           RESULT identical). On a RELEASE-channel box the eager
#                           content-hash check sees the mismatch → CHANNEL-BLESS
#                           re-stamps db.migration.content_hash to H_C (STATBUS-102;
#                           no hard-fail, no re-run) — the path for "the many who
#                           already succeeded at V".
#                           PENDING: the arc box installs dev-mode → migrationChannelClass
#                           classifies it local-dev → the bless can't fire yet, so the
#                           C-leg is SKIPPED awaiting the upgrade-arc deployment-mode
#                           decision (King/architect; STATBUS-102).
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

# _dump_working_failure_diagnostics — STATBUS-155 rider (mirrors
# postswap-health-park-arc.sh's _dump_health_park_failure_diagnostics): on ANY
# non-zero exit, pull B's own upgrade progress log + the daemon journal + its
# row state to STDERR before cleanup_vm reaps the VM, so a red run is
# self-sufficient without needing a kept VM. Best-effort throughout (|| true)
# — a diagnostics failure must never mask the real assertion error that
# triggered this trap. B-only (not B+C): this arc's C-leg is currently SKIPPED
# (see the "PENDING" block below) — C is built but never registered/scheduled,
# so it never has a row to dump.
_dump_working_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (B's progress log + daemon journal + row state) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── B's upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    else
        echo "  (no log_relative_file_path found for B's row — row absent or DB unreachable)" >&2
    fi
    echo "── daemon journal (statbus-upgrade@statbus.service, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit (B's row, commit_sha = ${B_FULL:-?}) ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(recovery_parked_reason,''), error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_working_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

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

# ── C: the channel-bless leg (V amended → release-channel re-stamp) — PENDING/SKIP ──
# BLOCKED on the upgrade-arc deployment-mode decision: the arc box installs as
# CADDY_DEPLOYMENT_MODE=development (vm-bootstrap.sh), and migrationChannelClass's
# dev-mode-wins precedence classifies it local-dev → the release-bless can't fire
# (the C-upgrade would error with the WIP-redo guidance, not re-stamp). Building the
# bless-leg awaits the King/architect deployment-mode decision (STATBUS-102). Until
# then this arc proves the A→B leg (V applies → completed) on the dev-mode box; the
# C-upgrade + the re-stamp / result-preserving assertions are SKIPPED. (C is built —
# C=${C_FULL:0:8} — so the leg lands cleanly once the mode decision does.)
echo ""
echo "⏭  SKIP (PENDING): the C-upgrade channel-bless re-stamp leg (C=${C_FULL:0:8}) —"
echo "    blocked on the upgrade-arc deployment-mode decision (dev-mode box → local-dev → bless can't fire)."

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS (PARTIAL): working arc A→B leg (V applied → completed; data intact; healthy). The C channel-bless re-stamp leg is PENDING the deployment-mode decision (STATBUS-102)."
