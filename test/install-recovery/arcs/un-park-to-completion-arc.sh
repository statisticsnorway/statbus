#!/bin/bash
# Arc: un-park-to-completion  (STATBUS-071 coverage map — the row AFTER
# restore-broke-reattempt; architect-pinned 2026-07-12: a RESOURCE-class park
# whose fix is genuinely EXTERNAL).
#
# WHAT THIS PROVES — the composition suffix the park family did not yet have end to
# end: a real upgrade PARKS on an external resource shortfall (disk), the operator
# fixes the resource, `./sb install` UN-PARKS, and the SAME row runs its one fresh
# attempt to 'completed' with data intact. The park SUBSTRATE itself (row state,
# alive-idle, parked-skip, un-park single-fresh-attempt) is already proven by
# postswap-health-park-arc + waves 9/10; this arc keeps the park asserts TIGHT and
# focuses on the NEW property: un-park → same row → completed.
#
# NOT a health-park leg: the health-park break is release-INTERNAL (the new version
# cannot serve past warmup — removing it would be a manual DB write = fabrication).
# Here the break is EXTERNAL (disk), so the un-parked fresh attempt genuinely
# SUCCEEDS once the disk is freed — the class the health-park arc's re-park cannot
# reach.
#
# THE PARK SITE (disk-check trace): the daemon parks BEFORE the docker pull via
# diskPrecheckReason (cli/internal/upgrade/service.go:5503), a structured statfs
# check (DiskFree(projDir), exec.go:24 → syscall.Statfs) against
# dockerStepMinFreeGB=5 (service.go:5495). executeUpgrade calls it at
# service.go:5657 right before `docker compose pull` and, on a non-empty reason,
# parkForDeterministicFailure fires — so we fill relative to that 5 GB floor. Note
# this is the DAEMON's docker-step floor, NOT the install ladder's STATBUS_MIN_DISK_GB
# (install.go:441, default 100 GB) — we pass STATBUS_MIN_DISK_GB=5 to `./sb install`
# so the ladder itself never refuses on the small arc VM.
#
# CONSTRUCTION: install A, populate data. Register B (working lineage — a genuine
# migration V that SUCCEEDS) so its images pre-download READY while the disk is
# healthy. THEN fill the disk below 5 GB and schedule B — the daemon claims and,
# at the pre-pull disk pre-check, parks (images already cached, but the pre-check is
# a headroom gate, so it parks regardless). Free the disk, `./sb install` un-parks,
# the same row completes.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-un-park-to-completion}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
PARK_WAIT_BUDGET_S="${PARK_WAIT_BUDGET_S:-600}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-1200}"
# Leave this much free after the fill — comfortably BELOW dockerStepMinFreeGB=5 so
# the pre-pull check parks deterministically, with enough headroom for the alive-idle
# box (DB keeps serving) across the brief park window before we free the disk.
FILL_TARGET_FREE_GB="${FILL_TARGET_FREE_GB:-4}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

UPGRADE_UNIT="statbus-upgrade@statbus.service"
FILL_FILE="tmp/arc-diskfill.bin"

# _dump_unpark_failure_diagnostics — STATBUS-155 rider (mirrors the park-family
# arcs): on ANY non-zero exit, pull B's progress log + the daemon journal + row
# state + the state-log to STDERR before cleanup_vm reaps the VM. Best-effort.
_dump_unpark_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (B's progress log + journal + row + state-log + df) ══════════" >&2
    local log_rel
    log_rel=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(log_relative_file_path,'') FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$log_rel" ]; then
        echo "── B's upgrade progress log (tmp/upgrade-logs/$log_rel) ──" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-logs/'$log_rel' 2>/dev/null" >&2 || echo "  (could not read the progress log)" >&2
    fi
    echo "── daemon journal ($UPGRADE_UNIT, last 400 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 400 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── B's row + disk free ──" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_attempts, recovery_parked_at IS NOT NULL AS parked, COALESCE(recovery_parked_reason,''), error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 || true
    VM_EXEC bash -c "df -h ~/statbus 2>/dev/null" >&2 || true
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT logged_at, old_state, new_state, (new_parked_at IS NOT NULL) AS now_parked, COALESCE(application_name,'') AS app, backend_pid FROM public.upgrade_state_log WHERE upgrade_id = (SELECT id FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1) ORDER BY id;\" | ./sb psql -x" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_unpark_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: un-park-to-completion  (RESOURCE-class park → un-park → completed)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  V=${V_VERSION}"
echo "════════════════════════════════════════════════════════════════"

# Transport-aware row reader (a psql failure reads as "?", never a state verdict).
row_cols_for() {
    local sha="$1"
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_parked_at IS NOT NULL, COALESCE(recovery_parked_reason,'') FROM public.upgrade WHERE commit_sha = '$sha' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r' || echo "?|?|?|(db-down)"
}
# df available bytes on ~/statbus's filesystem — the exact statfs DiskFree reads.
avail_bytes() {
    VM_EXEC bash -c "df -B1 --output=avail ~/statbus | tail -1 | tr -d ' '" 2>/dev/null | tr -d '\r'
}

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ── register B — images pre-download READY while the disk is still healthy ──
echo ""
dump_daemon_state "before B"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
echo "── register B ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
dump_signing_diagnostics "$B_FULL"

# ── fill the disk BELOW dockerStepMinFreeGB=5, BEFORE scheduling, so the daemon's
#    claim → executeUpgrade hits the pre-pull disk pre-check and parks. ──
echo ""
echo "── filling the disk below the 5 GB docker-step floor (leaving ~${FILL_TARGET_FREE_GB} GB) ──"
AVAIL=$(avail_bytes)
[[ "$AVAIL" =~ ^[0-9]+$ ]] || { echo "✗ could not read available bytes on ~/statbus (got '$AVAIL')" >&2; exit 1; }
TARGET_FREE=$(( FILL_TARGET_FREE_GB * 1024 * 1024 * 1024 ))
FILL_BYTES=$(( AVAIL - TARGET_FREE ))
[ "$FILL_BYTES" -gt 0 ] || { echo "✗ disk already below ${FILL_TARGET_FREE_GB} GB free before the fill (avail=$AVAIL) — cannot construct the pre-pull park deterministically" >&2; exit 1; }
VM_EXEC bash -c "cd ~/statbus && fallocate -l ${FILL_BYTES} ${FILL_FILE}" || { echo "✗ fallocate of ${FILL_BYTES} bytes failed" >&2; exit 1; }
AVAIL_AFTER=$(avail_bytes)
AVAIL_AFTER_GB=$(( AVAIL_AFTER / 1024 / 1024 / 1024 ))
echo "  free after fill: ${AVAIL_AFTER_GB} GB (was $(( AVAIL / 1024 / 1024 / 1024 )) GB)"
[ "$AVAIL_AFTER_GB" -lt 5 ] || { echo "✗ free space is ${AVAIL_AFTER_GB} GB after fill, not below the 5 GB docker-step floor — the pre-pull park would not fire" >&2; exit 1; }
echo "  ✓ disk below 5 GB — the daemon's pre-pull disk pre-check will park"

# ── schedule B → daemon claims + runs executeUpgrade → parks before the pull ──
echo ""
echo "── schedule B (daemon claims + executeUpgrade → pre-pull disk pre-check parks) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

echo ""
echo "── waiting for the RESOURCE park (recovery_parked_at IS NOT NULL), budget ${PARK_WAIT_BUDGET_S}s ──"
PARK_START=$(date +%s)
while true; do
    ELAPSED=$(( $(date +%s) - PARK_START ))
    ROW=$(row_cols_for "$B_FULL")
    PARKED_FLAG=$(echo "$ROW" | cut -d'|' -f3)
    if [ "$PARKED_FLAG" = "t" ]; then
        echo "  ✓ B parked (t+${ELAPSED}s): $ROW"
        break
    fi
    CUR_STATE=$(echo "$ROW" | cut -d'|' -f2)
    case "$CUR_STATE" in
        completed|failed|rolled_back)
            echo "✗ B reached terminal '$CUR_STATE' instead of parking — the disk-fill did not trip the pre-pull pre-check" >&2
            exit 1
            ;;
    esac
    if [ "$ELAPSED" -ge "$PARK_WAIT_BUDGET_S" ]; then
        echo "✗ B did not park within ${PARK_WAIT_BUDGET_S}s (last: $ROW)" >&2
        exit 1
    fi
    sleep 5
done

# ── ASSERT PARK (tight: resource class, before the pull). Capture id + reason NOW —
#    recovery_parked_reason is CLEARED on un-park, so it must be read while parked. ──
echo ""
echo "── assert park: state=in_progress, parked, reason names the disk floor; capture the row id ──"
ROW=$(row_cols_for "$B_FULL")
PARKED_ID=$(echo "$ROW" | cut -d'|' -f1)
PARK_STATE=$(echo "$ROW" | cut -d'|' -f2)
PARK_REASON=$(echo "$ROW" | cut -d'|' -f4)
echo "  parked row: id=$PARKED_ID state=$PARK_STATE reason=$PARK_REASON"
[[ "$PARKED_ID" =~ ^[0-9]+$ ]] || { echo "✗ could not read the parked row id (got '$PARKED_ID')" >&2; exit 1; }
[ "$PARK_STATE" = "in_progress" ] || { echo "✗ expected state='in_progress' while parked, got '$PARK_STATE'" >&2; exit 1; }
echo "$PARK_REASON" | grep -qiE "disk (nearly full|full)" || { echo "✗ recovery_parked_reason is not the disk/resource reason: $PARK_REASON" >&2; exit 1; }
echo "  ✓ RESOURCE park landed (in_progress, parked, disk reason), row id=$PARKED_ID"

# The box is ALIVE-IDLE while parked (the pull never ran, the OLD version keeps
# serving) — a valid read window (not a dead/teardown window): data must be intact.
echo ""
echo "── assert box alive-idle + data intact while parked (valid read window) ──"
assert_health_passes "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
echo "  ✓ healthy + data intact under the park"

# ── FREE the disk — the external fix. ──
echo ""
echo "── freeing the disk (removing the fill file) — the external resource fix ──"
VM_EXEC bash -c "cd ~/statbus && rm -f ${FILL_FILE}"
AVAIL_FREED_GB=$(( $(avail_bytes) / 1024 / 1024 / 1024 ))
echo "  free after removal: ${AVAIL_FREED_GB} GB"
[ "$AVAIL_FREED_GB" -ge 5 ] || { echo "✗ disk still below 5 GB after removing the fill file (${AVAIL_FREED_GB} GB) — the un-park attempt would re-park" >&2; exit 1; }
echo "  ✓ disk freed above the 5 GB floor"

# ── UN-PARK: ./sb install → one fresh attempt → the SAME row runs to completed. ──
echo ""
echo "── un-park: ./sb install (operator trigger) — disk is fixed, expect the SAME row to COMPLETE ──"
INSTALL_OUT=$(mktemp)
set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
    "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
    > "$INSTALL_OUT" 2>&1
INSTALL_RC=$?
set -e
cat "$INSTALL_OUT"
echo "  ./sb install (un-park) exit: $INSTALL_RC"
# Dispatch-log evidence (the un-park line is written before the row settles): the
# install must announce it un-parked, and exit 0 (the fresh attempt completes now
# that the disk is fixed — unlike the health-park re-park, which exits non-zero).
grep -qE "UN-PARKED upgrade id=[0-9]+" "$INSTALL_OUT" || { echo "✗ expected the 'UN-PARKED upgrade id=N' line in ./sb install's output" >&2; rm -f "$INSTALL_OUT"; exit 1; }
[ "$INSTALL_RC" -eq 0 ] || { echo "✗ ./sb install exited $INSTALL_RC on the un-park — expected 0 (the fresh attempt should complete with the disk freed)" >&2; rm -f "$INSTALL_OUT"; exit 1; }
rm -f "$INSTALL_OUT"
echo "  ✓ install logged UN-PARKED and exited 0"

# ── ASSERT COMPLETION (ruled terminal): the SAME row reached 'completed', park
#    cleared, V applied (anti-vacuity: the completion is genuine), data intact. ──
echo ""
echo "── assert completion: SAME row id=$PARKED_ID reached 'completed', un-parked, V applied, data intact ──"
ROW=$(row_cols_for "$B_FULL")
DONE_ID=$(echo "$ROW" | cut -d'|' -f1)
DONE_STATE=$(echo "$ROW" | cut -d'|' -f2)
DONE_PARKED=$(echo "$ROW" | cut -d'|' -f3)
echo "  final row: $ROW"
[ "$DONE_ID" = "$PARKED_ID" ] || { echo "✗ the completed row id=$DONE_ID is NOT the parked row id=$PARKED_ID — un-park must run the SAME row, not a fresh one" >&2; exit 1; }
[ "$DONE_STATE" = "completed" ] || { echo "✗ expected state='completed' after un-park, got '$DONE_STATE'" >&2; exit 1; }
[ "$DONE_PARKED" = "f" ] || { echo "✗ recovery_parked_at is still set after completion (parked=$DONE_PARKED) — un-park must clear it" >&2; exit 1; }
RC=$(fixture_row_count)
[ "$RC" = "1" ] || { echo "✗ V (V_VERSION=$V_VERSION) not applied: public.upgrade_arc_fixture count=$RC (want 1) — the completion is vacuous" >&2; exit 1; }
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_health_passes "$VM_NAME"
echo "  ✓ same row completed, park cleared, V applied, data intact, healthy"

echo ""
echo "PASS: un-park-to-completion — a real upgrade PARKED on the external disk shortfall (row $PARKED_ID, in_progress, disk reason, box alive-idle, data intact), the operator freed the disk, ./sb install un-parked, and the SAME row (id $PARKED_ID) ran its fresh attempt to 'completed' with V applied and data intact. The RESOURCE-park → external-fix → un-park-to-completion composition is proven end-to-end."
