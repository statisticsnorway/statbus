#!/bin/bash
# Scenario: 4-flagless-selfheal-at-target  (STATBUS-039's flagless self-heal —
# completeInProgressUpgrade converges a stray in_progress row when the box is
# genuinely at-target and NO flag is on disk to say otherwise)
#
# RENAMED + NARROWED from 4-rollback-abort-write-lands (STATBUS-071 §9(5),
# architect ruling on STATBUS-071 comments #16/#17, 2026-07-14). That scenario
# was a DUAL oracle: (1) the git-corrupt ABORT terminal write landing in one
# pass (STATBUS-136), and (2) this file's own surviving half — the SAME box's
# next flagless boot self-healing the row to 'completed'. Half (1) is now
# arc-proven for real (restore-broke-reattempt arc, run 29344519124 — a
# genuine dispatched upgrade + C9 parent-kill + a real detached-branch
# deletion, no fabrication) and has retired. This file keeps ONLY half (2).
# The rename re-keys the per-scenario stamp — this is honestly a NEW scenario
# and needs its own fresh green run to stamp, not a carry-over of the old
# file's history.
#
# WHY THIS STAYS A FABRICATION (STATBUS-071 comment #12's dead-producer
# doctrine, comment #17's self-correction of #16): construction is permitted
# ONLY for a state whose natural producer is a DEAD/fixed bug (sole prior
# member: 3-postswap-rune-wedge). This scenario's [at-target in_progress row
# + no flag] state is NOT dead — it has live producers, named here as
# REACHABILITY evidence, not as a legitimacy argument (comment #17 is explicit
# that live producers mean "must eventually be produced by the real path", not
# "fabrication is fine forever"):
#   (i)   recoverFromFlag's corrupt-flag-JSON branch: an unreadable flag file
#         is os.Remove'd and the row is left untouched (service.go:974-977) —
#         exactly [in_progress row, no flag] if the row was genuinely at-target.
#   (ii)  Service.Run's own boot sequence calls completeInProgressUpgrade
#         immediately after recoverFromFlag on EVERY boot (service.go:2130) —
#         the exact path a plain daemon restart exercises, no crash required.
#   (iii) The periodic poll-tick ALSO calls it (service.go:2235, "Belt:
#         reconcile any in_progress row whose final UPDATE was lost") — an
#         orphaned in_progress row self-heals even without any restart.
#   (iv)  tmp/ flag-file loss across a host reboot (ephemeral disk, tmpfs) —
#         an operational reality, not a code path.
# THIS FILE IS THE INTERIM NET, NOT A PERMANENT FABRICATION: it stands until a
# REAL-PATH successor goes green (queued, STATBUS-071 comment #17) — a real
# dispatched upgrade stalled at a known post-swap point, then TRUNCATE the
# flag file for real on the VM (the same "environment manipulation of real
# machinery state" genre the restore-broke-reattempt arc's ABORT half used,
# not a fabricated row) → the real corrupt-flag reader removes it → the next
# real boot's completeInProgressUpgrade converges. That successor deletes
# this file when it goes green, same pattern as rollback-abort-write-lands.
#
# THE ORACLE (narrower than the retired file — everything ABORT-related is
# gone: no corrupt git branch, no rollback(), no phase-patch to
# "new-sb-upgrading", no UPGRADE_CALLBACK wiring — completeInProgressUpgrade's
# completed path fires no callback at all):
#   fabricate an in_progress row whose commit_sha IS the box's own running
#   version (genuinely at-target — ground truth reads AtTarget, not Behind),
#   with NO flag file on disk at all (the flagless half needed it not to
#   exist, never to be created and later removed) -> restart the daemon (no
#   kill, no injection) -> completeInProgressUpgrade finds the orphan row,
#   verifies DB health + observed state, marks state='completed', error=NULL,
#   logs LabelCompletedFromInProgress -> flag stays absent throughout.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/4-flagless-selfheal-at-target.sh \
#     statbus-recovery-4-flagless-selfheal-at-target

set -euo pipefail

VM_NAME="${1:-statbus-recovery-4-flagless-selfheal-at-target}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
RESTART_WAIT_BUDGET_S="${RESTART_WAIT_BUDGET_S:-180}"
CONCLUDE_WAIT_BUDGET_S="${CONCLUDE_WAIT_BUDGET_S:-180}"
UPGRADE_UNIT="statbus-upgrade@statbus.service"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 4-flagless-selfheal-at-target  (STATBUS-039 — completeInProgressUpgrade's flagless self-heal)"
echo "  Initial release: $INSTALL_VERSION → at-target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

row_state() { VM_EXEC bash -c "cd ~/statbus && echo 'SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1;' | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "(db-down/?)"; }
flag_present() { VM_EXEC bash -c "test -f ~/statbus/tmp/upgrade-in-progress.json && echo yes || echo no" 2>/dev/null | tr -d ' \r\n' || echo "no"; }
row_state_and_error() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state, COALESCE(error,'') FROM public.upgrade ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r'; }

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

echo ""
echo "── staging HEAD + checking out the working tree (the box must GENUINELY be at HEAD for ground truth to read AtTarget) ──"
upload_sb_to_vm "$VM_NAME"
VM_EXEC bash -c "cd ~/statbus && git fetch --depth 1 origin $HEAD_SHA 2>/dev/null || true; git -c advice.detachedHead=false checkout $HEAD_SHA"
VM_EXEC bash -c "cd ~/statbus && ./sb config generate"

echo ""
echo "── catching db.migration up to HEAD's migration set (must be fully applied, or ground truth reads Behind instead of AtTarget) ──"
VM_EXEC bash -c "cd ~/statbus && timeout 600 ./sb migrate up --verbose"

[ "$(flag_present)" = "no" ] || { echo "✗ a flag file already exists before fabrication — construction invalid (this scenario is specifically the FLAGLESS case)" >&2; exit 1; }

echo ""
echo "── fabricating the in_progress row ONLY — no flag file, ever (the flagless half never creates one, let alone removes one) ──"
# Row shape mirrors fabricate_resume_state's own INSERT (data-helpers.sh) but
# WITHOUT the flag-file write that helper always performs — that helper is
# for the (row + flag) fabrication family (rune-wedge, the churn variant);
# this scenario's whole point is a row with NO flag, so it does not call it.
UPSERT_SQL=$(cat << SQL
WITH input(commit_sha) AS (VALUES ('${HEAD_SHA}'))
INSERT INTO public.upgrade
  (commit_sha, committed_at, commit_tags, release_status, summary,
   has_migrations, commit_version, state, scheduled_at, started_at,
   completed_at, rolled_back_at, error,
   log_relative_file_path, skipped_at, dismissed_at, superseded_at,
   docker_images_status, release_builds_status)
SELECT
  input.commit_sha,
  now(),
  '{}'::text[],
  'commit'::public.release_status_type,
  'harness 4-flagless-selfheal-at-target (STATBUS-071 comment #16/#17)',
  false,
  'harness-' || substring(input.commit_sha for 8),
  'in_progress'::public.upgrade_state,
  now(),
  now(),
  NULL, NULL, NULL,
  'harness-' || substring(input.commit_sha for 8) || '.log', NULL, NULL, NULL,
  'ready'::public.docker_images_status_type,
  'ready'::public.release_builds_status_type
FROM input
ON CONFLICT (commit_sha) DO UPDATE SET
  state                  = 'in_progress'::public.upgrade_state,
  scheduled_at            = now(),
  started_at              = now(),
  completed_at            = NULL,
  rolled_back_at          = NULL,
  error                   = NULL,
  skipped_at              = NULL,
  dismissed_at            = NULL,
  superseded_at           = NULL,
  recovery_attempts       = 0,
  recovery_parked_at      = NULL,
  recovery_parked_reason  = NULL,
  docker_images_status    = 'ready'::public.docker_images_status_type,
  release_builds_status   = 'ready'::public.release_builds_status_type
RETURNING id;
SQL
)
SQL_FILE=$(mktemp /tmp/harness-fabricate-inprogress-row-XXXXXX.sql)
printf '%s\n' "$UPSERT_SQL" > "$SQL_FILE"
chmod 644 "$SQL_FILE"
scp -O "${SSH_OPTS[@]}" "$SQL_FILE" root@"$VM_IP":/tmp/harness-fabricate-inprogress-row.sql >/dev/null
rm -f "$SQL_FILE"
ROW_ID=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
    "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb psql -q -t -A < /tmp/harness-fabricate-inprogress-row.sql' && rm -f /tmp/harness-fabricate-inprogress-row.sql" \
    2>&1 | tr -d ' \r\n')
[[ "$ROW_ID" =~ ^[0-9]+$ ]] || { echo "✗ could not parse fabricated row id from psql output: '$ROW_ID'" >&2; exit 1; }
echo "  ✓ row fabricated: id=$ROW_ID commit_sha=$HEAD_SHA state=in_progress (no flag written)"
[ "$(flag_present)" = "no" ] || { echo "✗ a flag file appeared during row fabrication — construction invalid" >&2; exit 1; }

echo ""
echo "── restarting upgrade-service unit onto HEAD (no kill, no injection — the ordinary boot sequence finds the orphan row and self-heals it) ──"
vm_restart_unit "$UPGRADE_UNIT"
echo "  ✓ unit restart issued"

echo ""
echo "── waiting for the row to leave 'in_progress' (budget ${CONCLUDE_WAIT_BUDGET_S}s) ──"
START=$(date +%s)
FINAL_STATE="in_progress"
while :; do
    NOW=$(date +%s); ELAPSED=$((NOW - START))
    FINAL_STATE=$(row_state)
    if [ "$FINAL_STATE" != "in_progress" ] && [ "$FINAL_STATE" != "(db-down/?)" ]; then
        echo "  [OBSERVE] row left in_progress after ${ELAPSED}s: state=$FINAL_STATE"
        break
    fi
    if [ "$ELAPSED" -ge "$CONCLUDE_WAIT_BUDGET_S" ]; then
        echo "✗ row still '$FINAL_STATE' after ${CONCLUDE_WAIT_BUDGET_S}s — the flagless self-heal did not conclude" >&2
        exit 1
    fi
    sleep 5
done

FINAL_ROW=$(row_state_and_error)
FINAL_STATE=$(echo "$FINAL_ROW" | cut -d'|' -f1)
FINAL_ERROR=$(echo "$FINAL_ROW" | cut -d'|' -f2-)
echo "[OBSERVE] final row: state=$FINAL_STATE error='${FINAL_ERROR}'"
[ "$FINAL_STATE" = "completed" ] || { echo "✗ expected the flagless self-heal to converge to 'completed', got '$FINAL_STATE'" >&2; exit 1; }
[ -z "$FINAL_ERROR" ] || { echo "✗ expected error IS NULL after the self-heal, got '$FINAL_ERROR'" >&2; exit 1; }
echo "  ✓ state='completed', error IS NULL"

echo ""
echo "── confirming the product named its own label in the journal (LabelCompletedFromInProgress) ──"
VM_EXEC bash -c "journalctl --user -u '$UPGRADE_UNIT' --no-pager 2>/dev/null | grep -F 'upgrade row [completed-from-in-progress]'" >/dev/null \
    || { echo "✗ journal does not show 'upgrade row [completed-from-in-progress]' — completeInProgressUpgrade's own completed-path log line" >&2; exit 1; }
echo "  ✓ journal shows completeInProgressUpgrade's own [completed-from-in-progress] label"

assert_flag_file_absent "$VM_NAME"
echo "  ✓ flag absent — it was never written (the flagless half of the property, by construction)"

echo ""
echo "── settling after the unit's own boot (no restart loop expected — nothing here ever crashes) ──"
SETTLE_START=$(date +%s)
while :; do
    NOW=$(date +%s); ELAPSED=$((NOW - SETTLE_START))
    STATE=$(VM_EXEC systemctl --user is-active "$UPGRADE_UNIT" 2>/dev/null | tr -d ' \r\n' || echo "?")
    [ "$STATE" = "active" ] && { echo "  ✓ unit active (settled after ${ELAPSED}s)"; break; }
    if [ "$ELAPSED" -ge "$RESTART_WAIT_BUDGET_S" ]; then
        echo "✗ unit did not settle to 'active' within ${RESTART_WAIT_BUDGET_S}s (last state: $STATE)" >&2
        exit 1
    fi
    sleep 3
done

# Bound=1: this scenario never kills or crashes anything — the ONE restart in
# its entire lifetime is the deliberate `vm_restart_unit` this script itself
# issues to trigger the boot-time reconciliation. Anything higher means the
# unit is looping, which the flagless self-heal (a clean, one-pass DB write)
# should never cause.
assert_systemd_restart_counter_bounded "$VM_NAME" "$UPGRADE_UNIT" 1

assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

echo ""
echo "PASS: 4-flagless-selfheal-at-target (an orphan in_progress row, genuinely at-target and flagless, self-heals to state='completed'/error=NULL on the very next ordinary boot — no kill, no injection, no flag ever written; completeInProgressUpgrade's own [completed-from-in-progress] label confirmed in the journal; unit alive-idle, NRestarts bounded at 1, data intact)"
