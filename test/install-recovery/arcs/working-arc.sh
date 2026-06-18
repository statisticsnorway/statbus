#!/bin/bash
# Arc: working → working-fixed  (STATBUS-071 increment (c); doc-012 §9 (c))
#
# The FIRST real upgrade arc + the STATBUS-072 re-stamp proven end-to-end on a
# real VM, driven entirely through the Albania mechanism (register + schedule →
# the upgrade SERVICE runs it autonomously — NO quiesce, NO ./sb install).
#
# Arc shape (A → B → C, all post-086 commits):
#   A = base_sha            install fresh, pinned (install_statbus_at_sha).
#   B = A + V               V is a genuine migration that SUCCEEDS (a real,
#                           observable schema change). Upgrade A→B applies V and
#                           records it in db.migration with content_hash H_B.
#   C = B with V amended    C edits V IN PLACE (§7 Option-1: bytes change → hash
#                           H_C ≠ H_B, RESULT identical) AND declares V in
#                           migrations/amendments.tsv. Upgrade B→C: eager
#                           content-hash check sees H_C ≠ H_B, finds V in the
#                           amendments set → RE-STAMPS db.migration.content_hash
#                           to H_C (does NOT hard-fail, does NOT re-run V). This
#                           is the real 072 path for "the many who already
#                           succeeded at V".
#
# Inputs (env): BASE_SHA, B_FULL, C_FULL (40-hex), B_BRANCH, C_BRANCH, V_VERSION
#   (the 14-digit migration version the construct job created). VM name = $1.

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

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: working → working-fixed  (re-stamp / Albania autonomous)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  C=${C_FULL:0:8}  V=${V_VERSION}"
# DIAGNOSTIC (STATBUS-071): did the ephemeral arc-signer pubkey thread through?
# (run-arc env SB_ARC_TRUSTED_SIGNER ← construct.outputs.arc_pubkey). Empty here
# = the threading broke (→ install_statbus_at_sha skips the trust injection →
# verifyCommitSignature rejects B as untrusted). Show length, not the full key.
echo "  SB_ARC_TRUSTED_SIGNER: ${SB_ARC_TRUSTED_SIGNER:+PRESENT (${#SB_ARC_TRUSTED_SIGNER} chars): ${SB_ARC_TRUSTED_SIGNER%% *} ...}${SB_ARC_TRUSTED_SIGNER:-MISSING/EMPTY}"
echo "════════════════════════════════════════════════════════════════"

# dump_signing_diagnostics <sha> — permanent DIAGNOSTIC (AGENTS.md: build the
# tool, don't just debug). Dumps the full trust chain state the daemon will use
# to verify <sha>, right before scheduling: the .env.config signer, the .env
# signer (post config-generate), tmp/allowed-signers (what git verify-commit
# reads), and <sha>'s own signature/signing-key. A mismatch here pinpoints WHERE
# the ephemeral-key trust broke (absent var → absent .env.config → absent .env →
# absent allowed-signers → wrong key). Best-effort: never fails the arc.
dump_signing_diagnostics() {
    local sha="$1"
    echo "  ┌─ signing diagnostics (trust chain for ${sha:0:8}) ─"
    echo "  │ .env.config:    $(VM_EXEC bash -c "cd ~/statbus && grep UPGRADE_TRUSTED_SIGNER .env.config || echo '(none)'" 2>/dev/null | tr '\n' ' ')"
    echo "  │ .env:           $(VM_EXEC bash -c "cd ~/statbus && grep UPGRADE_TRUSTED_SIGNER .env || echo '(none)'" 2>/dev/null | tr '\n' ' ')"
    echo "  │ allowed-signers:$(VM_EXEC bash -c "cd ~/statbus && cat tmp/allowed-signers 2>/dev/null || echo '(no file)'" 2>/dev/null | tr '\n' '|')"
    echo "  │ commit sig:     $(VM_EXEC bash -c "cd ~/statbus && git log -1 --format='%G? key=%GK' $sha 2>/dev/null || echo '(unreadable)'" 2>/dev/null | tr '\n' ' ')"
    echo "  └─"
}

# arc_to <commit_sha> <commit_branch> <label> — drive ONE upgrade through the
# real register→ready→schedule→service-runs→terminal path (0-happy-upgrade
# phases 4-6, generalized). Pre-fetches the target branch so the daemon's
# executeUpgrade can `git checkout` it. Fails loud unless the row reaches
# state='completed' within the budget.
arc_to() {
    local sha="$1" branch="$2" label="$3"
    echo ""
    echo "── arc → ${label} (${sha:0:8}) ──"
    # Make the target commit present on the VM (daemon checks it out).
    VM_EXEC bash -c "cd ~/statbus && git fetch origin $branch && git cat-file -e $sha"

    echo "  register ${label}"
    VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $sha 2>&1 | tail -20"
    echo "  wait for candidate ready"
    wait_for_upgrade_candidate_ready "$VM_NAME" "$sha" "$TICK_WAIT_S"

    dump_signing_diagnostics "$sha"

    echo "  schedule ${label} (DB trigger → daemon claims + runs executeUpgrade)"
    VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $sha 2>&1 | tail -20"

    local start_ts elapsed state final=""
    start_ts=$(date +%s)
    while true; do
        elapsed=$(( $(date +%s) - start_ts ))
        if [ "$elapsed" -ge "$UPGRADE_BUDGET_S" ]; then
            echo "✗ ${label}: no terminal state within ${UPGRADE_BUDGET_S}s" >&2
            VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, commit_sha, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
            exit 1
        fi
        state=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$sha' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
        case "$state" in
            completed|failed|rolled_back) final="$state"; echo "  ${label}: state='$state' (t+${elapsed}s)"; break ;;
        esac
        sleep 5
    done
    if [ "$final" != "completed" ]; then
        echo "✗ ${label} did NOT reach 'completed' (got '$final')" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$sha' ORDER BY id DESC LIMIT 3;\" | ./sb psql" >&2 || true
        exit 1
    fi
}

# fixture_row_count / migration_content_hash — small psql readers for the arc's
# observable schema change (public.upgrade_arc_fixture) and V's ledger hash.
fixture_row_count() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.upgrade_arc_fixture;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR"
}
migration_content_hash() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT content_hash FROM db.migration WHERE version = ${V_VERSION};\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR"
}
migration_row_count() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM db.migration WHERE version = ${V_VERSION};\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR"
}

# ── A: fresh install pinned to base_sha ──
bootstrap_install_test_vm "$VM_NAME" ""
echo ""
echo "── install A (base_sha ${BASE_SHA:0:8}) ──"
install_statbus_at_sha "$VM_NAME" "$BASE_SHA"
assert_health_passes "$VM_NAME"

# The arc is driven by the upgrade SERVICE (A's daemon — A=base_sha is post-086,
# so it HAS register/schedule + executeUpgrade). Verify the unit is active before
# driving the arc; the schedule below relies on it claiming the scheduled row.
UNIT_STATE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
[ "$UNIT_STATE" = "active" ] || { echo "✗ upgrade-service unit not active after install A (state=$UNIT_STATE)" >&2; exit 1; }
echo "  ✓ upgrade-service active (daemon will run the arc)"

echo ""
echo "── populate demo data + snapshot ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ── B: V applies (the many-who-succeed precondition) ──
arc_to "$B_FULL" "$B_BRANCH" "B (V applies)"
echo "── assert V applied + recorded ──"
RC=$(fixture_row_count)
[ "$RC" = "1" ] || { echo "✗ V not applied: public.upgrade_arc_fixture count=$RC (want 1)" >&2; exit 1; }
H_B=$(migration_content_hash)
[ -n "$H_B" ] && [ "$H_B" != "ERR" ] || { echo "✗ no content_hash for V=$V_VERSION after B" >&2; exit 1; }
echo "  ✓ V applied (fixture row present); H_B=${H_B:0:16}…"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"

# ── C: V amended in place + declared in amendments.tsv → RE-STAMP (no re-run) ──
arc_to "$C_FULL" "$C_BRANCH" "C (V amended → re-stamp)"
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
