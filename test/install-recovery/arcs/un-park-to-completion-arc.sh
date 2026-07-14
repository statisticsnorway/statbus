#!/bin/bash
# Arc: un-park-to-completion  (STATBUS-071 coverage map — the row AFTER
# restore-broke-reattempt; architect-ruled 2026-07-14, comment #22: a RESOURCE-class
# park whose fix is genuinely EXTERNAL, on the ONLY lineage that can reach it).
#
# THE DOCTRINAL LAW THIS ARC OBEYS (architect, STATBUS-071 #22; the general law,
# stated once here so the next reader does not re-derive it from a red run):
#   UNDER 145's ATOMICITY, A PARK IS AN AT-TARGET / UNVERIFIABLE PHENOMENON.
#   Anything positively-BEHIND target rolls back instead. So a construction chasing
#   a park must hold the ledger AT-TARGET — which, for a failure site BEFORE the
#   migrations run (the pre-pull disk pre-check), means a NO-DELTA lineage: B carries
#   NO migration, so at that check the ledger max == on-disk max and the box is
#   genuinely at-target (ObservedAlreadyAtNew, service.go newSbUpgradingFailure) →
#   the resource failure PARKS. A delta-carrying B is positively-Behind at that same
#   check → its resource failure ROLLS BACK. (Second time a park construction moved
#   for 145: doc-028 reclassified the boot-migrate park the same way.)
#
# THE ROW'S TWO ARMS (this ruling split the map row into its two truths):
#   ARM (i) — DELTA upgrade + resource failure ⇒ ROLLBACK + re-trigger. Already
#     PROVEN by run 29360596950 (the timed-fill construction on the WORKING lineage
#     rolled back on the full disk — the RIGHT operator story for a delta: a serving
#     box at the old version + "free disk space, then re-trigger"). The map row
#     CREDITS that run; this arc asserts nothing for arm (i).
#   ARM (ii) — NO-DELTA upgrade + resource failure ⇒ resource-class PARK + external
#     fix + un-park-to-completion. This arc IS arm (ii), on the codeonly lineage.
#
# WHAT THIS ARC PROVES (arm ii): a real NO-DELTA upgrade PARKS on an external
# resource shortfall (disk) at the pre-pull check while genuinely at-target; the
# park sirens exactly once; the parked box boots alive-idle; the operator frees the
# disk; `./sb install` UN-PARKS; and the SAME row runs its ONE fresh attempt to
# 'completed' — with ZERO restores anywhere (nothing to restore: at-target all
# along), data intact.
#
# NOT a health-park leg: the health-park break is release-INTERNAL (the new version
# cannot serve past warmup — removing it would be a manual DB write = fabrication).
# Here the break is EXTERNAL (disk), so the un-parked fresh attempt genuinely
# SUCCEEDS once the disk is freed — the class the health-park arc's re-park cannot
# reach. And unlike health-park (a delta lineage that parks on the POST-migration
# health leg), this arc parks PRE-migration, which is why it needs the no-delta
# lineage to stay at-target.
#
# THE TWO-CHECK DISK LANDSCAPE (the load-bearing fact — do NOT re-learn it from a
# red run). executeUpgrade guards disk TWICE, and the two checks have OPPOSITE
# outcomes. A naive "fill the disk, then schedule" trips the WRONG one and the row
# FAILS instead of parking (this arc's first red run: "Insufficient disk space:
# 3 GB free" — a fail, not a park):
#
#   CHECK 1 — PRE-SWAP, FAILS (service.go:5011). At the very top of executeUpgrade,
#     before the backup, DiskFree(projDir) < 5 GB → failUpgrade with
#     "Insufficient disk space: %d GB free (need at least 5 GB for backup +
#     images)". This is a hard FAIL (state=failed), NOT a park. A disk already
#     full when the daemon claims the row dies here — the park site is never
#     reached.
#
#   CHECK 2 — POST-SWAP, PARKS (service.go:5657). After the binary swap and the
#     exit-42 handoff, the resumed NEW binary calls diskPrecheckReason(StepImagePull)
#     (service.go:5503, DiskFree vs dockerStepMinFreeGB=5, service.go:5495) right
#     before `docker compose pull`; a non-empty reason → parkForDeterministicFailure
#     ("disk nearly full: %d GB free (< 5 GB needed) before image pull"). THIS is a
#     PARK (state=in_progress, recovery_parked_at set, box alive-idle).
#
# So the disk must be HEALTHY at CHECK 1 and FULL at CHECK 2. The construction fills
# the disk in the gap BETWEEN them. The gap is generous, not a microsecond race:
#   backup (pre-swap, service.go:~5105) → warm-up image pull (pre-swap, caches B's
#   images while disk is healthy) → binary swap → updateFlagNewSbSwapped stamps
#   phase=new-sb-swapped + BackupPath (service.go:5368) → os.Exit(42) (service.go:5380)
#   → systemd RestartSec=30 (ops/statbus-upgrade.service) → new binary boots,
#   deferred checkout, reaches CHECK 2.
# The flag file (tmp/upgrade-in-progress.json) carries phase across the exit-42
# restart and PERSISTS during the ~30 s RestartSec wait — so polling it for
# phase=new-sb-swapped gives a seconds-to-tens-of-seconds window to land the fill
# before CHECK 2, not a knife-edge.
#
# BACKUP IS PRE-FILL BY CONSTRUCTION (rollback stays clean): the snapshot is
# finalised at service.go:~5105 and stamped into flag.BackupPath at
# updateFlagNewSbSwapped (5368) — both BEFORE phase=new-sb-swapped is observable and
# thus before our fill. The backup we restore-from on any rollback was taken on a
# healthy disk; the fill never touches it.
#
# Note dockerStepMinFreeGB=5 is the DAEMON's docker-step floor, NOT the install
# ladder's STATBUS_MIN_DISK_GB (install.go:441, default 100 GB) — we pass
# STATBUS_MIN_DISK_GB=5 to `./sb install` so the ladder itself never refuses on the
# small arc VM.
#
# CONSTRUCTION: install A, populate data. Register B (CODEONLY / no-delta lineage —
# B = A + a non-migration marker, NO migration V — so the box stays at-target at the
# pre-pull check and parks rather than rolling back) so its images pre-download READY
# while the disk is healthy. Schedule B on a HEALTHY disk (CHECK 1 passes). Poll the
# flag for phase=new-sb-swapped (backup + swap done), THEN fallocate below 5 GB so
# the resumed binary parks at CHECK 2 (images already cached, but the pre-check is a
# headroom gate, so it parks regardless). Free the disk, `./sb install` un-parks, the
# SAME row completes with ZERO restores. Defensive: if the fill loses the race and B
# COMPLETES without parking, fail with THAT story named — never a generic wrong-state
# assert.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH. NO V_VERSION — the codeonly
# lineage carries no migration by design. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-un-park-to-completion}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
# The pre-swap phase (claim → backup → warm-up image pull ~2 GB → binary swap →
# phase=new-sb-swapped stamp) can take a few minutes on a small VM; budget for it.
SWAP_WAIT_BUDGET_S="${SWAP_WAIT_BUDGET_S:-600}"
PARK_WAIT_BUDGET_S="${PARK_WAIT_BUDGET_S:-600}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-1200}"
# Leave this much free after the fill — comfortably BELOW dockerStepMinFreeGB=5 so
# the pre-pull check parks deterministically, with enough headroom for the alive-idle
# box (DB keeps serving) across the brief park window before we free the disk.
FILL_TARGET_FREE_GB="${FILL_TARGET_FREE_GB:-4}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
# NO V_VERSION: the codeonly lineage carries no migration — asserting a fixture
# version here would be a category error (arm ii is at-target with zero delta).

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

UPGRADE_UNIT="statbus-upgrade@statbus.service"
FILL_FILE="tmp/arc-diskfill.bin"
# Siren (park-callback) log + the alive-idle settle budget (mirrors the health-park
# arc — the RestartSec=30 auto-restart hold-off must elapse before "alive-idle" is
# a real verdict, not a between-restarts snapshot).
CALLBACK_LOG="/tmp/un-park-callback-log.txt"
UNIT_ACTIVE_WAIT_BUDGET_S="${UNIT_ACTIVE_WAIT_BUDGET_S:-90}"

# state_log_rollback_count — how many times B's row has entered 'rolled_back' in
# public.upgrade_state_log. Arm (ii) is at-target all along, so a restore/rollback
# must NEVER happen; this is the DB-level "zero restores" oracle (a restore is the
# rollback path). Returns "?" on a transport/DB failure (never a false zero).
state_log_rollback_count() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id = (SELECT id FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1) AND new_state = 'rolled_back';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"
}

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
echo "  Arc: un-park-to-completion  (arm ii: no-delta at-target park → un-park → completed)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  (codeonly lineage — no migration V)"
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
# The upgrade flag's phase field (tmp/upgrade-in-progress.json). Empty when the flag
# is absent OR still pre-swap: phase has `omitempty`, so PhaseOldSbUpgrading ("") is
# OMITTED from the JSON — no "phase" key means pre-swap. A non-empty value
# (new-sb-swapped / new-sb-upgrading) means the binary swap has committed and
# CHECK 1 is behind us: the safe moment to fill.
flag_phase() {
    # Must return 0 even when the flag is absent or has no phase key (the normal
    # pre-swap case): under `set -euo pipefail` a grep-no-match would otherwise
    # abort the arc at `PHASE=$(flag_phase)`. The trailing `|| true` absorbs it.
    local json
    json=$(VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null" 2>/dev/null) || true
    echo "$json" \
        | grep -oE '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' | head -1 | tr -d '\r' || true
}

# ── A: install + prepare (bootstrap → install A → health → trust arc → populate) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-arc data snapshot: $DATA_SNAPSHOT"

# ── configure the park-callback (siren) so the arc can assert it fires exactly
#    once on the park. Same pattern as postswap-health-park-arc: a callback SCRIPT
#    transferred as a FILE (never inline — the sudo -i re-quoting layer eats bare
#    $VARNAME), wired via .env.config so it survives every `sb config generate`. ──
echo ""
echo "── writing the park-callback (siren) script + wiring UPGRADE_CALLBACK ──"
CALLBACK_SCRIPT_LOCAL=$(mktemp)
cat > "$CALLBACK_SCRIPT_LOCAL" << CALLBACKSCRIPT
#!/bin/sh
echo "\$STATBUS_EVENT \$(date -u +%FT%TZ)" >> $CALLBACK_LOG
CALLBACKSCRIPT
scp -O "${SSH_OPTS[@]}" "$CALLBACK_SCRIPT_LOCAL" root@"$VM_IP":/tmp/un-park-callback.sh >/dev/null
rm -f "$CALLBACK_SCRIPT_LOCAL"
ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
    'mv /tmp/un-park-callback.sh /home/statbus/un-park-callback.sh && chown statbus:statbus /home/statbus/un-park-callback.sh && chmod 0755 /home/statbus/un-park-callback.sh'
VM_EXEC bash -c "rm -f $CALLBACK_LOG"
# Trailing-newline guard: .env.config's last line has no trailing \n, so a naive
# >> would glue UPGRADE_CALLBACK onto it.
VM_EXEC bash -c 'cd ~/statbus && (tail -c1 .env.config | grep -q "^$" || printf "\n" >> .env.config) && printf "UPGRADE_CALLBACK=/home/statbus/un-park-callback.sh\n" >> .env.config'
VM_EXEC bash -c "cd ~/statbus && ./sb config generate"
VM_EXEC bash -c "grep '^UPGRADE_CALLBACK=' ~/statbus/.env" || { echo "✗ UPGRADE_CALLBACK did not land in .env after config generate" >&2; exit 1; }
echo "  ✓ siren configured (survives config generate; runCallback reads .env fresh at fire time)"

# ── register B — images pre-download READY while the disk is still healthy ──
echo ""
dump_daemon_state "before B"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
echo "── register B ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"
dump_signing_diagnostics "$B_FULL"

# ── schedule B on a HEALTHY disk — CHECK 1 (pre-swap, service.go:5011) must PASS.
#    Filling before this point would trip CHECK 1 and FAIL the row (this arc's
#    first red run). The daemon claims, runs the backup + warm-up pull + swap. ──
echo ""
echo "── schedule B (disk HEALTHY so CHECK 1 passes; daemon claims → backup → swap) ──"
AVAIL_AT_SCHEDULE=$(avail_bytes)
AVAIL_AT_SCHEDULE_GB=$(( AVAIL_AT_SCHEDULE / 1024 / 1024 / 1024 ))
[ "$AVAIL_AT_SCHEDULE_GB" -ge 5 ] || { echo "✗ disk is only ${AVAIL_AT_SCHEDULE_GB} GB free at schedule time — CHECK 1 (service.go:5011) would FAIL the row before it can reach the park site" >&2; exit 1; }
echo "  disk at schedule: ${AVAIL_AT_SCHEDULE_GB} GB free (≥ 5 GB — CHECK 1 passes)"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $B_FULL 2>&1 | tail -20"

# ── WATCH for the swap: poll the flag for phase=new-sb-swapped. Once it is
#    non-empty the backup + binary swap are DONE (CHECK 1 is behind us) and the
#    resumed binary is ~30 s (RestartSec) from CHECK 2 — the window to fill. ──
echo ""
echo "── watching the flag for the binary swap (phase=new-sb-swapped), budget ${SWAP_WAIT_BUDGET_S}s ──"
SWAP_START=$(date +%s)
while true; do
    ELAPSED=$(( $(date +%s) - SWAP_START ))
    PHASE=$(flag_phase)
    if [ -n "$PHASE" ]; then
        echo "  ✓ swap observed (t+${ELAPSED}s): flag phase='$PHASE' — backup + swap done, CHECK 1 passed"
        break
    fi
    # If B fails/parks/completes before we ever see a swap, the swap window was
    # missed (or CHECK 1 fired despite the healthy schedule) — surface it now.
    ROW=$(row_cols_for "$B_FULL")
    CUR_STATE=$(echo "$ROW" | cut -d'|' -f2)
    PARKED_FLAG=$(echo "$ROW" | cut -d'|' -f3)
    if [ "$PARKED_FLAG" = "t" ]; then
        echo "✗ B parked BEFORE we observed the swap — unexpected; the fill never ran, so this is not the post-swap CHECK-2 park we intend to prove (last: $ROW)" >&2
        exit 1
    fi
    case "$CUR_STATE" in
        failed|rolled_back)
            echo "✗ B reached terminal '$CUR_STATE' during the pre-swap phase — CHECK 1 (service.go:5011) likely failed the row despite the healthy schedule; the disk must stay ≥ 5 GB until the swap (last: $ROW)" >&2
            exit 1
            ;;
        completed)
            echo "✗ B COMPLETED before we ever observed the swap — the swap-watch poll was too slow to catch phase=new-sb-swapped; widen SWAP_WAIT poll cadence (last: $ROW)" >&2
            exit 1
            ;;
    esac
    if [ "$ELAPSED" -ge "$SWAP_WAIT_BUDGET_S" ]; then
        echo "✗ never observed phase=new-sb-swapped within ${SWAP_WAIT_BUDGET_S}s (last row: $ROW, last phase: '$PHASE')" >&2
        exit 1
    fi
    sleep 3
done

# ── FILL the disk below dockerStepMinFreeGB=5, now that the swap is done, so the
#    resumed binary parks at CHECK 2 (service.go:5657) before the docker pull. ──
echo ""
echo "── filling the disk below the 5 GB docker-step floor (leaving ~${FILL_TARGET_FREE_GB} GB) ──"
AVAIL=$(avail_bytes)
[[ "$AVAIL" =~ ^[0-9]+$ ]] || { echo "✗ could not read available bytes on ~/statbus (got '$AVAIL')" >&2; exit 1; }
TARGET_FREE=$(( FILL_TARGET_FREE_GB * 1024 * 1024 * 1024 ))
FILL_BYTES=$(( AVAIL - TARGET_FREE ))
[ "$FILL_BYTES" -gt 0 ] || { echo "✗ disk already below ${FILL_TARGET_FREE_GB} GB free before the fill (avail=$AVAIL) — cannot construct the CHECK-2 park deterministically" >&2; exit 1; }
VM_EXEC bash -c "cd ~/statbus && fallocate -l ${FILL_BYTES} ${FILL_FILE}" || { echo "✗ fallocate of ${FILL_BYTES} bytes failed" >&2; exit 1; }
AVAIL_AFTER=$(avail_bytes)
AVAIL_AFTER_GB=$(( AVAIL_AFTER / 1024 / 1024 / 1024 ))
echo "  free after fill: ${AVAIL_AFTER_GB} GB (was $(( AVAIL / 1024 / 1024 / 1024 )) GB)"
[ "$AVAIL_AFTER_GB" -lt 5 ] || { echo "✗ free space is ${AVAIL_AFTER_GB} GB after fill, not below the 5 GB docker-step floor — CHECK 2 would not park" >&2; exit 1; }
echo "  ✓ disk below 5 GB — the resumed binary's CHECK 2 pre-pull pre-check will park"

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
        completed)
            # The defensive branch (foreman rider): the fill lost the race to
            # CHECK 2. Name that exact story — do NOT report a generic wrong-state.
            echo "✗ B COMPLETED without parking — the disk-fill LOST THE RACE to CHECK 2 (service.go:5657): the resumed binary passed the pre-pull pre-check with a healthy disk before our fallocate landed (B's images were cached by the pre-swap warm-up, so the post-swap pull was fast). The fill must land in the RestartSec≈30 s window after phase=new-sb-swapped; re-run, or shorten the poll→fill latency (last: $ROW)" >&2
            exit 1
            ;;
        failed|rolled_back)
            echo "✗ B reached terminal '$CUR_STATE' instead of parking — the disk-fill did not trip CHECK 2 (or tripped a fail-class check instead) (last: $ROW)" >&2
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

# NEVER ROLLED BACK (the arm (i)/(ii) fork, the doctrinal crux): a no-delta B is
# at-target at the pre-pull check, so it PARKS. If this row EVER entered
# 'rolled_back', the lineage was not actually at-target (a stray migration slipped
# in) — the whole arm-(ii) premise is void. Assert zero rollbacks in the state-log.
ROLLBACKS=$(state_log_rollback_count)
[ "$ROLLBACKS" = "0" ] || { echo "✗ B's state-log shows $ROLLBACKS rollback(s) — arm (ii) must be at-target and PARK, never roll back (a rollback means B carried a delta / was Behind)" >&2; exit 1; }
echo "  ✓ zero rollbacks in the state-log — at-target park, not a Behind rollback"

# SIREN fired EXACTLY ONCE on the park (STATBUS-131 park-callback contract).
echo ""
echo "── assert the park siren fired exactly once ──"
SIREN_COUNT=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$SIREN_COUNT" = "1" ] || { echo "✗ expected exactly 1 park-callback (siren) line, got $SIREN_COUNT" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "cat $CALLBACK_LOG" | grep -q "^parked " || { echo "✗ siren line does not carry STATBUS_EVENT=parked" >&2; exit 1; }
echo "  ✓ exactly one STATBUS_EVENT=parked siren fired"

# The box is ALIVE-IDLE while parked (the pull never ran, the OLD version keeps
# serving) — a valid read window (not a dead/teardown window): the daemon unit is
# active-idle (not crash-looping) and data must be intact. Wait out the RestartSec
# hold-off first so "active" is a settled verdict, not a between-restarts snapshot.
echo ""
echo "── assert box alive-idle (daemon active, not crash-looping) + data intact while parked ──"
echo "── waiting out the auto-restart hold-off (budget ${UNIT_ACTIVE_WAIT_BUDGET_S}s) before the alive-idle check ──"
sleep "$UNIT_ACTIVE_WAIT_BUDGET_S"
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"
assert_health_passes "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
echo "  ✓ daemon alive-idle, healthy + data intact under the park"

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
# ONE fresh attempt: the un-park line must appear EXACTLY once (a single grant, not
# a churn of re-un-parks). Count it rather than merely grep -q.
UNPARK_LINES=$(grep -cE "UN-PARKED upgrade id=[0-9]+" "$INSTALL_OUT" || true)
[ "$UNPARK_LINES" = "1" ] || { echo "✗ expected exactly ONE 'UN-PARKED upgrade id=N' line (one fresh attempt), got $UNPARK_LINES" >&2; rm -f "$INSTALL_OUT"; exit 1; }
[ "$INSTALL_RC" -eq 0 ] || { echo "✗ ./sb install exited $INSTALL_RC on the un-park — expected 0 (the fresh attempt should complete with the disk freed)" >&2; rm -f "$INSTALL_OUT"; exit 1; }
rm -f "$INSTALL_OUT"
echo "  ✓ install logged UN-PARKED exactly once (one fresh attempt) and exited 0"

# ── ASSERT COMPLETION (ruled terminal): the SAME row reached 'completed', park
#    cleared, data intact — and ZERO restores anywhere (arm ii is at-target all
#    along, so nothing was ever restored). NO fixture/V assertion: the codeonly
#    lineage carries no migration by design (that absence is the whole point). ──
echo ""
echo "── assert completion: SAME row id=$PARKED_ID reached 'completed', un-parked, ZERO restores, data intact ──"
ROW=$(row_cols_for "$B_FULL")
DONE_ID=$(echo "$ROW" | cut -d'|' -f1)
DONE_STATE=$(echo "$ROW" | cut -d'|' -f2)
DONE_PARKED=$(echo "$ROW" | cut -d'|' -f3)
echo "  final row: $ROW"
[ "$DONE_ID" = "$PARKED_ID" ] || { echo "✗ the completed row id=$DONE_ID is NOT the parked row id=$PARKED_ID — un-park must run the SAME row, not a fresh one" >&2; exit 1; }
[ "$DONE_STATE" = "completed" ] || { echo "✗ expected state='completed' after un-park, got '$DONE_STATE'" >&2; exit 1; }
[ "$DONE_PARKED" = "f" ] || { echo "✗ recovery_parked_at is still set after completion (parked=$DONE_PARKED) — un-park must clear it" >&2; exit 1; }
# ZERO restores anywhere (arm ii's signature): the row must never have rolled back —
# not at the park, not during the un-park attempt. At-target all along means there
# was nothing to restore; a restore would be a correctness violation of the ruling.
ROLLBACKS_FINAL=$(state_log_rollback_count)
[ "$ROLLBACKS_FINAL" = "0" ] || { echo "✗ B's state-log shows $ROLLBACKS_FINAL rollback(s) across the whole arc — arm (ii) must complete with ZERO restores (nothing to restore: at-target throughout)" >&2; exit 1; }
# The siren fired once (at the park) and NOT again through the un-park→complete leg
# (completion is not a park event).
SIREN_FINAL=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$SIREN_FINAL" = "1" ] || { echo "✗ siren count is $SIREN_FINAL at completion (expected still 1 — the park sirens once; un-park→complete must not re-siren)" >&2; exit 1; }
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_health_passes "$VM_NAME"
echo "  ✓ same row completed, park cleared, ZERO restores, siren still once, data intact, healthy"

echo ""
echo "PASS: un-park-to-completion (arm ii, no-delta lineage) — a real CODE-ONLY upgrade PARKED at-target on the external disk shortfall (row $PARKED_ID, in_progress, disk reason, siren once, daemon alive-idle, zero rollbacks, data intact), the operator freed the disk, ./sb install un-parked (one fresh attempt), and the SAME row (id $PARKED_ID) ran to 'completed' with ZERO restores anywhere and data intact. The at-target RESOURCE-park → external-fix → un-park-to-completion composition is proven end-to-end on the only lineage that can reach it. (Arm (i), delta→rollback, is credited to run 29360596950.)"
