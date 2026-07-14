#!/bin/bash
# Arc: cross-version-rename-handoff  (STATBUS-164 half #2 — oracle ii, the run-oracle
# for the on-disk phase serialization rename's legacy-alias READ).
#
# WHAT THIS PROVES — the alias read on its MAINLINE path, on a real VM, across the
# rename boundary. The unit round-trips (legacy_phase_bytes_test.go) prove the
# decode chokepoint in isolation; only THIS arc proves it end-to-end where it
# actually fires: a box installed at a PRE-RENAME release hands a mid-upgrade flag
# carrying the OLD wire byte "post_swap" to a POST-RENAME binary, which must
# normalize it via legacyPhaseByteAliases and resume forward to 'completed'.
#
# THE HANDOFF (why 'completed' IS the proof):
#   A (pre-rename base) runs executeUpgrade to the binary swap, stamps the flag
#   Phase="post_swap" (its literal — A predates the rename), replaces ./sb with the
#   target binary on disk, and exits 42. systemd restarts the unit onto the TARGET
#   (post-rename) binary, whose recoverFromFlag reads the flag; its UnmarshalJSON
#   chokepoint normalizes "post_swap" → PhaseNewSbSwapped ("new-sb-swapped"), routes
#   to the forward-resume branch, migrates, and converges. If the alias were absent
#   the target binary would hit its FLAG_PHASE_UNKNOWN loud-stop on "post_swap" and
#   the row would NEVER reach 'completed' — so a completed row, flag removed, zero
#   rollback IS the alias-read proof.
#
# BASE PIN: A = a fixed PRE-RENAME release commit (default 730b5001c, rc.05 —
# tagged, image-built, an ancestor of the rename commit 0e04a9613 where the source
# still reads `PhaseNewSbSwapped = "post_swap"`). This is the fleet's real starting
# point. It is pinned independent of the run's own base_sha (unlike every other arc,
# whose base == the run SHA); the target is the run's post-rename commit. Both images
# already exist — A's as the rc.05 release, the target's as the run's per-commit
# build — so no synthetic construct lineage is needed. Update the pin only if rc.05's
# image is GC'd (then pin a newer still-pre-rename release).
#
# Inputs (env): PRE_RENAME_BASE_SHA (40-hex, pinned pre-rename), TARGET_SHA (40-hex,
#   the post-rename target), TARGET_BRANCH (a fetchable ref containing TARGET_SHA).
#   VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-cross-version-rename-handoff}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-1800}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"

: "${PRE_RENAME_BASE_SHA:?PRE_RENAME_BASE_SHA required (a pinned pre-rename release commit)}"
: "${TARGET_SHA:?TARGET_SHA required (the post-rename target commit)}"
: "${TARGET_BRANCH:?TARGET_BRANCH required (a fetchable ref containing TARGET_SHA)}"

# arc_prepare_box installs $BASE_SHA — point it at the PINNED pre-rename base rather
# than the run's own base_sha. This is the whole cross-version twist: base and target
# straddle the rename boundary.
export BASE_SHA="$PRE_RENAME_BASE_SHA"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

# _dump_cross_version_failure_diagnostics — STATBUS-155 rider (mirrors
# working-arc.sh): on ANY non-zero exit, pull the target row's progress log + the
# daemon journal + flag + row state to STDERR before cleanup_vm reaps the VM, so a
# red run is self-sufficient. Best-effort throughout (|| true).
_dump_cross_version_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (target progress log + daemon journal + flag + row) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha = '${TARGET_SHA:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── target upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    else
        echo "  (no log_relative_file_path found for the target row — row absent or DB unreachable)" >&2
    fi
    echo "── daemon journal (statbus-upgrade@statbus.service, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── flag file + row state at exit (target commit_sha = ${TARGET_SHA:-?}) ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, rolled_back_at IS NOT NULL AS rolled_back, error FROM public.upgrade WHERE commit_sha = '${TARGET_SHA:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_cross_version_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: cross-version-rename-handoff  (STATBUS-164 half #2 legacy-alias read)"
echo "  A (pre-rename base) = ${PRE_RENAME_BASE_SHA:0:8}  →  target (post-rename) = ${TARGET_SHA:0:8}"
echo "  A stamps flag \"post_swap\"; the target binary must read it via the alias and converge."
echo "════════════════════════════════════════════════════════════════"

# ── A: install the PINNED pre-rename base + prepare (bootstrap → install → health →
#      trust → populate). BASE_SHA was exported to PRE_RENAME_BASE_SHA above. ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ── The cross-version upgrade: A (pre-rename) → target (post-rename). The daemon
#    runs executeUpgrade, swaps the binary, stamps "post_swap", exits 42; the target
#    binary resumes through the alias read and converges. arc_to fails loud unless the
#    target row reaches 'completed'. ──
arc_to "$TARGET_SHA" "$TARGET_BRANCH" "target (post-rename) — resumes through the legacy-byte alias" "completed"

# ── Assertions: the handoff crossed the rename boundary cleanly. ──
echo ""
echo "── assert the boundary handoff converged cleanly ──"

# The target row is completed and was NOT rolled back (a broken alias read would have
# stalled at FLAG_PHASE_UNKNOWN or rolled back, never completed).
ROLLED_BACK=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT rolled_back_at IS NOT NULL FROM public.upgrade WHERE commit_sha = '$TARGET_SHA' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
[ "$ROLLED_BACK" = "f" ] || { echo "✗ target row was rolled back (rolled_back_at set) — the alias handoff did not resume forward" >&2; exit 1; }
echo "  ✓ target row completed, zero rollback"

# The binary swap + tree checkout completed: the box's HEAD is now the target commit.
HEAD_ON_BOX=$(VM_EXEC bash -c "cd ~/statbus && git rev-parse HEAD" 2>/dev/null | tr -d ' \r\n')
[ "$HEAD_ON_BOX" = "$TARGET_SHA" ] || { echo "✗ box HEAD is $HEAD_ON_BOX, expected the target $TARGET_SHA — the swap/checkout did not complete the handoff" >&2; exit 1; }
echo "  ✓ box checked out to the target commit (${TARGET_SHA:0:8}) — binary swap + tree handoff completed"

# The flag is gone, data survived the cross-version upgrade, and the box is healthy.
assert_flag_file_absent "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: cross-version-rename-handoff — a pre-rename box (${PRE_RENAME_BASE_SHA:0:8}) handed a \"post_swap\" flag to the post-rename binary (${TARGET_SHA:0:8}), which read it through the legacy-byte alias, resumed forward, and converged to 'completed' with data intact, healthy, zero rollback. The alias read is proven on its mainline."
