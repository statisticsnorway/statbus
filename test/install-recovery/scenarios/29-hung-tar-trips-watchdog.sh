#!/bin/bash
# Scenario 29: hung-tar-trips-watchdog  (#11 CHANGE 1 + #3 progress-gating)
#
# Class:                 archive-backup-stall-active-phase-watchdog (reused)
# Class kind:            Stall (held PAST the effective trip → watchdog must fire)
# Source:                plan upgrade-resume-structural-whole.md (#3 + CHANGE 1)
#
# THE DISTINCTION THIS DRAWS (vs scenario 26):
#   Scenario 26 holds the archiveBackup stall for 180 s and asserts the unit
#   SURVIVES (NRestarts delta ≤ 1). That passes because the #3 progress-gated
#   watchdog's effective trip is stallThreshold (3 min) + WatchdogSec (120 s) ≈
#   5 min — a 180 s stall is UNDER it, so the gate hasn't closed yet.
#
#   THIS scenario holds the SAME inject PAST the effective trip (default 330 s >
#   300 s) and asserts the OPPOSITE: the watchdog FIRES. That is the heart of
#   #3 + CHANGE 1 — "advancing survives, HUNG is caught." A genuinely hung tar
#   emits no checkpoints (the inject stalls BEFORE the tar runs, so
#   lastAdvanceAt never advances), the gate closes after 3 min, WATCHDOG=1
#   stops, and ~120 s later systemd SIGABRTs the unit. NRestarts climbs.
#
#   This is the falsifiable complement of scenario 26: 26 proves a sub-trip
#   stall is tolerated (no false-trip of a slow-but-bounded step); 29 proves a
#   beyond-trip hang is NOT tolerated (a real hang is reaped, not pinged
#   forever — closing the task-#37 blind-watchdog hole).
#
# WHY archiveBackup is the chosen hang site, and why it's SAFE to let it trip:
#   archiveBackup runs AFTER the terminal state='completed' UPDATE + flag
#   removal (§4a FIX A), so even when the watchdog SIGABRTs the unit mid-stall,
#   the upgrade is ALREADY completed and the flag is gone — the next start finds
#   no flag and no-ops. So this scenario asserts: (a) the watchdog DID fire
#   during the hang (NRestarts climbed — the gate works), AND (b) the system
#   still converges to a coherent completed state after release (the trip was
#   harmless because completion already persisted). Both together = the gate is
#   real AND firing it costs nothing.
#
# advancing-tar-survives (the other half of #11): a LIVE long tar (checkpoints
#   firing → lastAdvanceAt advancing → watchdog fed → NOT killed) is NOT
#   exercised here — the harness's tiny test DB tars in seconds, so a
#   multi-minute ADVANCING tar can't be produced without a large backup. That
#   half is covered by: the Go guard TestCheckpointLineBumpsLastAdvance (a
#   checkpoint line bumps lastAdvanceAt), the operator's empirical confirmation
#   that GNU tar 1.35 --checkpoint=N --checkpoint-action=echo emits the expected
#   per-checkpoint lines on the deployment hosts, and scenario 26 (a real
#   sub-trip archiveBackup that completes). See the scenario-29 note in the
#   harness README.
#
# Hetzner-runnability:
#   READY (real systemd needed to observe WatchdogSec firing). Inject site
#   archive-backup-stall-active-phase-watchdog is on master (merge 86fb9a454);
#   the #3 gating + #11 checkpoint feed are on master too.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/29-hung-tar-trips-watchdog.sh \
#     statbus-recovery-29

set -euo pipefail

VM_NAME="${1:-statbus-recovery-29}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
# Hold PAST the effective trip: stallThreshold (3 min = 180 s) + WatchdogSec
# (120 s) = 300 s. 330 s default gives ~30 s margin so the SIGABRT reliably
# fires during the hold. Load-bearing — must exceed 300 s.
STALL_HOLD_S="${STALL_HOLD_S:-330}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-1200}"   # 20 min — covers the 330s hang + restart + post-release convergence

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

UNIT="statbus-upgrade@statbus.service"
RELEASE_FILE="/tmp/stall-release-hung-tar"
DROPIN_DIR="\$HOME/.config/systemd/user/${UNIT}.d"
DROPIN_FILE="$DROPIN_DIR/hung-tar-inject.conf"

trap '
    rc=$?
    VM_EXEC bash -c "
        rm -f $RELEASE_FILE 2>/dev/null || true
        rm -f $DROPIN_FILE 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user reset-failed $UNIT 2>/dev/null || true
        systemctl --user restart $UNIT 2>/dev/null || true
    " 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 29: hung-tar-trips-watchdog  (#11 CHANGE 1 + #3 gating)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "  Stall hold: ${STALL_HOLD_S}s (> effective trip 300s = 180s gate + 120s WatchdogSec)"
echo ""
echo "  Complement of scenario 26 (180s, survives): a HUNG tar held past the"
echo "  trip must make the gated watchdog FIRE (NRestarts climbs), then converge"
echo "  harmlessly on release (completion already persisted before archiveBackup)."
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

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

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — stage HEAD on the VM (so the upgrade runs HEAD's code)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── staging HEAD on the VM ──"
HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
ip=$(hcloud server ip "$VM_NAME")
upload_sb_to_vm "$VM_NAME"
scp -O "${SSH_OPTS[@]}" \
    "$LIB_DIR/../fixtures/scenario_26_stage_head.sh" \
    root@"$VM_IP":/tmp/scenario_29_stage_head.sh
VM_EXEC bash /tmp/scenario_29_stage_head.sh "$HEAD_LOCAL"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — stop service, install drop-in + release file (stop BEFORE
# fabricate so the running unit can't pick up the row before the inject is in
# place — same ordering as scenario 26).
# ─────────────────────────────────────────────────────────────────────────
NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

echo ""
echo "── stopping service and installing hung-tar inject drop-in ──"
VM_EXEC systemctl --user stop "$UNIT" 2>/dev/null || true

_dropin_script=$(mktemp /tmp/harness-install-dropin-XXXXXX.sh)
cat > "$_dropin_script" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/${UNIT}.d"
DROPIN_FILE="\$DROPIN_DIR/hung-tar-inject.conf"
mkdir -p "\$DROPIN_DIR"
cat > "\$DROPIN_FILE" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_INJECT_AT=archive-backup-stall-active-phase-watchdog
Environment=STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=$RELEASE_FILE
DROPIN_EOF
touch $RELEASE_FILE
systemctl --user daemon-reload
SCRIPT_EOF
chmod 644 "$_dropin_script"
scp -O "${SSH_OPTS[@]}" "$_dropin_script" root@"$VM_IP":/tmp/harness-install-dropin.sh
rm -f "$_dropin_script"
VM_EXEC bash /tmp/harness-install-dropin.sh
ssh "${SSH_OPTS[@]}" root@"$VM_IP" "rm -f /tmp/harness-install-dropin.sh" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — fabricate scheduled upgrade row (service stopped → no race)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── fabricating scheduled public.upgrade row for HEAD ──"
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — restart the unit; it dispatches the upgrade, reaches archiveBackup
# (AFTER the terminal completed-UPDATE), and stalls there with no checkpoints.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── restarting unit (will dispatch upgrade, stall in archiveBackup) ──"
VM_EXEC systemctl --user reset-failed "$UNIT" 2>/dev/null || true
VM_EXEC systemctl --user start "$UNIT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — hold the stall PAST the effective trip; the gated watchdog must
# fire (the gate closes at +180s of no-advance; SIGABRT ~120s later).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── holding the hung-tar stall for ${STALL_HOLD_S}s (> 300s effective trip) ──"
echo "   expect: gate closes at ~180s no-advance → WATCHDOG=1 stops → systemd SIGABRTs ~120s later → NRestarts climbs"
sleep "$STALL_HOLD_S"

NRESTARTS_DURING=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
echo "  NRestarts at hold-end: $NRESTARTS_DURING (baseline=$NRESTARTS_BASELINE)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 8 — LOAD-BEARING assertion: the watchdog FIRED during the hang.
# A hung tar held past the trip MUST have caused at least one SIGABRT-restart
# (the gate stopped pinging). delta == 0 means the gate did NOT close — the
# blind-watchdog hole (#37) would be back.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── #3+#11 gate-fired check (LOAD-BEARING) ──"
DELTA_DURING=$(( NRESTARTS_DURING - NRESTARTS_BASELINE ))
if [ "$NRESTARTS_DURING" = "?" ]; then
    echo "✗ could not read NRestarts" >&2
    exit 1
fi
if [ "$DELTA_DURING" -lt 1 ]; then
    echo "✗ NRestarts did NOT climb during a ${STALL_HOLD_S}s hung tar (delta=$DELTA_DURING)." >&2
    echo "  The progress-gated watchdog should have STOPPED pinging after ~180s of no advance" >&2
    echo "  (a stalled-before-tar archiveBackup emits no checkpoints → lastAdvanceAt frozen)," >&2
    echo "  letting WatchdogSec SIGABRT the unit. delta=0 means the gate never closed — the" >&2
    echo "  task-#37 blind-watchdog hole (pings forever past a hang) would be back." >&2
    exit 1
fi
echo "  ✓ watchdog FIRED during the hang (NRestarts +$DELTA_DURING) — the gate closed on a real hang"

# ─────────────────────────────────────────────────────────────────────────
# Phase 9 — release the stall; assert HARMLESS convergence. Because
# archiveBackup runs AFTER the terminal completed-UPDATE + flag removal (FIX A),
# the row is already 'completed' and the flag gone — so despite the SIGABRT(s),
# the next start no-ops and the system is coherent at the new version.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── releasing the stall; expect harmless convergence (completion already persisted) ──"
VM_EXEC bash -c "rm -f $RELEASE_FILE"

START_TS=$(date +%s)
FINAL_STATE=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge $(( UPGRADE_BUDGET_S - STALL_HOLD_S )) ]; then
        echo "✗ upgrade row did not reach a terminal state within budget after release" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    case "$STATE" in
        completed|failed|rolled_back)
            FINAL_STATE="$STATE"
            echo "  ✓ upgrade row reached state='$STATE' (t+${elapsed}s after release)"
            break
            ;;
    esac
    sleep 5
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 10 — convergence assertions. The completed-UPDATE persisted BEFORE
# archiveBackup, so 'completed' is the expected terminal state (the SIGABRT
# during the tar was harmless). Data intact, flag gone, healthy.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks (the trip was harmless: completion persisted pre-tar) ──"
if [ "$FINAL_STATE" != "completed" ]; then
    echo "✗ expected state='completed' (the terminal UPDATE ran BEFORE archiveBackup per FIX A, so the hung-tar SIGABRT can't have prevented completion); got '$FINAL_STATE'" >&2
    exit 1
fi
echo "  ✓ row state='completed' — completion persisted before the hung tar (FIX A), trip was harmless"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: hung-tar-trips-watchdog"
echo "  (a tar hung past the 5m effective trip made the #3 progress-gated watchdog"
echo "   FIRE — NRestarts climbed, proving the gate closes on a real hang, not the"
echo "   #37 blind ping-forever — and the system still converged to 'completed'"
echo "   because §4a FIX A persisted completion BEFORE archiveBackup, so the trip"
echo "   was harmless. Complement of scenario 26's sub-trip survives-case.)"
