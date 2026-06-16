#!/bin/bash
# Scenario: 3-postswap-migration-timeout  (C12 — boot-migrate vs systemd watchdog, STATBUS-012 net)
#
# Class:                 migration-slower-than-systemd-unit-timeout
# Class kind:            Stall
# Forensics tag:         Race B (Layer 1) → STATBUS-012 (boot-migrate edition)
# Source forensics:      doc-005 (backlog) — boot-migrate watchdog gap: verdict,
#                        severity, RED reproducer, fix design
#
# WHAT THIS TESTS (the product contract):
#   A migration that runs longer than WatchdogSec (120s in
#   ops/statbus-upgrade.service) MUST NOT get the upgrade service
#   watchdog-killed. Since executeUpgrade ALWAYS hands off after the
#   binary swap (Step 6b, service.go: checkout → procure → PostSwap
#   flag → exit-42), the migration delta of EVERY service-path upgrade
#   is consumed by boot-migrate-up (service.go:1644) on the post-swap
#   boot — BEFORE recoverFromFlag / applyPostSwap. So the watchdog
#   cover must exist AT THE BOOT-MIGRATE SITE: an always-ping
#   WATCHDOG=1 ticker for the duration of the migrate subprocess,
#   bounded by the shared 30-min migrate timeout (STATBUS-012 fix).
#
#   Without that cover (the STATBUS-012 gap): zero WATCHDOG=1 sources
#   exist during boot-migrate — the idle heartbeat ticker is created
#   AFTER boot-migrate in Run(), the applyPostSwap gated ticker is not
#   armed yet, and the migrate child neither pings nor could be heard
#   (NotifyAccess defaults to main). systemd SIGABRTs the unit at
#   ~READY+120s, Restart=always re-runs it, the stall re-arms, and the
#   unit kill-loops (~160s/cycle → StartLimitBurst=5/600s never trips
#   → loops indefinitely). That is the rune-wedge shape, WatchdogSec
#   edition.
#
# HISTORY — why this scenario was rewritten (2026-06-11):
#   The previous version dispatched the upgrade INLINE (./sb install in
#   tmux). Inline there is NO systemd unit in the flow at all (no
#   NOTIFY_SOCKET → sdNotify no-ops → no watchdog anywhere), and its
#   stall fired at the inline crash-recovery boot-migrate; the
#   NRestarts assertion read a unit that was not driving the install —
#   vacuously green. It validated nothing about the watchdog. This
#   rewrite dispatches through the REAL systemd service (the King's
#   Option-A doctrine: test the production path), where the watchdog
#   actually arms — and the stall lands exactly at the unprotected
#   boot-migrate of the post-swap boot.
#
# Trigger logic (full systemd-unit dispatch; drop-in env lands on the
# exit-42 restart — the post-swap boot — NOT on the dispatching unit):
#   1. Install at INSTALL_VERSION (default v2026.05.2), populate demo
#      data, snapshot counts.
#   2. Stage HEAD on the VM (fixtures/stage-head.sh: checkout +
#      pre-tag COMMIT_SHORT images for the compose-pull fallback).
#   3. Plant the synthetic stall-target migration (untracked,
#      timestamp 20991231235959) so the post-swap boot-migrate has a
#      guaranteed ≥1 pending migration regardless of seed level.
#   4. Write the systemd user drop-in with the C12 env vars + touch
#      the release file + daemon-reload — WITHOUT restarting the
#      unit. A running process's env is untouched by daemon-reload;
#      the env applies at the NEXT unit start, which is exactly the
#      exit-42 post-swap restart. The dispatching run stays
#      inject-free; the stall deterministically lands on the
#      post-swap boot's `sb migrate up` child.
#   5. Fabricate a public.upgrade row (state=scheduled) for HEAD and
#      wake the service via NOTIFY (./sb upgrade apply).
#   6. The unit runs executeUpgrade → preSwap backup → checkout →
#      procure → PostSwap flag → exit-42. systemd restarts it WITH
#      the inject env; the fresh boot's boot-migrate spawns
#      `sb migrate up`, which parks in inject.StallHere (runPsqlFile,
#      BEFORE psql is invoked — so watchdog kills during the hold
#      leave no in-container orphans).
#   7. Confirm the stall (migrate child stable) AND that the flag is
#      Phase=post_swap (proves we are at the post-swap boot's
#      boot-migrate, pre-recoverFromFlag — the STATBUS-012 site).
#   8. Snapshot NRestarts as the POST-STALL baseline (the exit-42
#      handoff itself legitimately incremented NRestarts once;
#      baselining after the stall excludes it).
#   9. Hold STALL_HOLD_S=180s (> WatchdogSec=120s).
#  10. LOAD-BEARING: NRestarts delta from the post-stall baseline
#      MUST be 0 and the unit Result MUST NOT be 'watchdog'. With the
#      STATBUS-012 fix, the boot-migrate always-ping ticker keeps the
#      unit alive across the hold. Without it, systemd SIGABRTs at
#      ~120s and the delta climbs — the RED that reproduces the gap.
#  11. Remove the release file → the migration proceeds → boot-migrate
#      completes the delta → recoverFromFlag → resumePostSwap →
#      applyPostSwap (its migrate is a no-op) → upgrade completes.
#  12. Assert terminal state, data intact, flag absent, bounded
#      restart counter, health.
#
# Hetzner-runnability:
#   READY. Reuses suite-proven machinery only: stage-head fixture
#   (archivebackup scenarios), drop-in pattern (watchdog-reconnect),
#   fabricate_scheduled_upgrade_row + NOTIFY wake (watchdog-reconnect),
#   wait_for_inject_stall_ready (kill scenarios), synthetic stall
#   migration (this scenario's previous version).
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-migration-timeout.sh \
#     statbus-recovery-3-postswap-migration-timeout

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-migration-timeout}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
STALL_HOLD_S="${STALL_HOLD_S:-180}"            # > WatchdogSec=120; load-bearing
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"    # post-release budget: migrate + resume + completion

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

RELEASE_FILE="/tmp/stall-release-c12"
UNIT="statbus-upgrade@statbus.service"
SYNTHETIC_MIG="20991231235959_migration-stall-target"

trap '
    rc=$?
    # Best-effort cleanup so a failed scenario does not leave the stall
    # armed (matters if KEEP_VM=1 is set for debugging — cleanup_vm
    # destroys the VM otherwise). Removing the release file FIRST
    # unblocks any parked migrate child; then drop the drop-in so a
    # later unit start is inject-free.
    VM_EXEC bash -c "rm -f $RELEASE_FILE 2>/dev/null || true; rm -f \$HOME/.config/systemd/user/statbus-upgrade@statbus.service.d/inject.conf 2>/dev/null || true; systemctl --user daemon-reload 2>/dev/null || true" 2>/dev/null || true
    cleanup_vm "$VM_NAME"
    exit $rc
' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-migration-timeout  (C12 / STATBUS-012 — boot-migrate vs watchdog)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD (service dispatch)"
echo "  Stall hold: ${STALL_HOLD_S}s (> WatchdogSec=120s)"
echo ""
echo "  Tests the boot-migrate watchdog cover: the post-swap boot's"
echo "  migration run must survive >WatchdogSec without the unit being"
echo "  SIGABRT'd. RED on the STATBUS-012 gap (kill loop at ~120s);"
echo "  GREEN with the always-ping ticker fix."
echo "════════════════════════════════════════════════════════════════"

HEAD_LOCAL=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
SHORT_SHA=$(echo "$HEAD_LOCAL" | cut -c1-8)
echo "  HEAD: $HEAD_LOCAL ($SHORT_SHA)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 1 — bootstrap + initial install at older release
# ─────────────────────────────────────────────────────────────────────────
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — populate with demo data (operator-shape baseline)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — stage HEAD on the VM (checkout + image pre-tag fallback)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── staging HEAD on the VM (fixtures/stage-head.sh) ──"
upload_sb_to_vm "$VM_NAME"
scp -O "${SSH_OPTS[@]}" "$LIB_DIR/../fixtures/stage-head.sh" root@"$VM_IP":/tmp/stage-head.sh
VM_EXEC bash /tmp/stage-head.sh "$HEAD_LOCAL"

# Pre-stage the HEAD binary as ./sb so executeUpgrade's procurement
# (Step 6b) takes the pre-staged-binary skip (sbAlreadyAtCommit,
# service.go buildBinaryOnDisk) instead of `make -C cli build` — the VM
# has NO Go toolchain, so without this the upgrade rolls back at
# procurement and the post-swap boot (the STATBUS-012 site) is never
# reached. Run-1 of this scenario failed exactly there (row=rolled_back,
# stall never fired). This is the suite's established pattern: the
# pre-rewrite version of this scenario carried the same load-bearing
# `cp /tmp/sb ./sb` in its install script. (`sb` is gitignored, so the
# upgrade's own `git checkout` does not touch it.)
echo "── pre-staging HEAD binary as ./sb (procurement short-circuit) ──"
VM_EXEC bash -c "cp /tmp/sb ~/statbus/sb && chmod +x ~/statbus/sb"
# PAIRING ASSERTION (fail loud, fail early). upload_sb_to_vm rebuilds the
# binary from CURRENT local HEAD at upload time, while HEAD_LOCAL (the
# row target) was captured at scenario start. The backlog board lives in
# THIS git repo, so any board edit landing mid-run moves HEAD and poisons
# the pairing: sbAlreadyAtCommit misses, procurement attempts `make -C
# cli build` on the Go-less VM, and the upgrade rolls back pre-swap —
# run-3 failed exactly this way (binary 4f28c46d vs target 908191f0).
DEPLOYED_COMMIT=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version 2>/dev/null" | grep -oE 'commit [0-9a-f]{8}' | head -1 | awk '{print $2}' || echo "")
HEAD_PREFIX=$(echo "$HEAD_LOCAL" | cut -c1-8)
echo "  deployed ./sb commit: ${DEPLOYED_COMMIT:-?} (row target: $HEAD_PREFIX)"
if [ "$DEPLOYED_COMMIT" != "$HEAD_PREFIX" ]; then
    echo "✗ pre-staged binary commit (${DEPLOYED_COMMIT:-?}) != row target ($HEAD_PREFIX)" >&2
    echo "  A commit landed between scenario start and the binary upload (board edits" >&2
    echo "  live in this repo and move HEAD). Hold commits while the scenario runs," >&2
    echo "  then relaunch." >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 3c — restart the unit onto the HEAD binary BEFORE dispatch
#
# The DISPATCHING process must run HEAD's code, not INSTALL_VERSION's:
# run-4 proved the v2026.05.2 binary has NO sbAlreadyAtCommit
# pre-staged-binary skip (git show v2026.05.2 → zero matches), so the
# old dispatcher always attempts `make -C cli build` on the Go-less VM
# → BINARY_BUILD_FAILED → pre-swap rollback, regardless of the cp above.
# Restarting here puts the HEAD binary (with the skip) in charge of
# executeUpgrade. Ordering is load-bearing:
#   - AFTER the cp (the restarted unit must BE the HEAD binary);
#   - BEFORE the synthetic migration is planted (this restart's
#     boot-migrate consumes any real delta cleanly — the synthetic must
#     survive until the post-swap boot);
#   - BEFORE the drop-in is armed (this restart must be inject-free;
#     the env lands only on the exit-42 restart).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── restarting unit onto the HEAD binary (clean, pre-arm) ──"
vm_restart_unit "$UNIT"
# Let this boot's migrate settle before planting the synthetic. The real
# v2026.05.2→HEAD delta IS applied here (the installed seed sits at the
# INSTALL_VERSION's migration level, run-5 journal evidence) — budget
# 300s. The pgrep pattern uses the [/] bracket trick: run-5's poll
# matched its OWN ssh/sudo wrapper (whose cmdline contains the literal
# pattern) and never settled; '[/]sb migrate up' does not contain the
# substring it matches, so the wrapper is invisible while the real
# child (/home/statbus/statbus/sb migrate up) still matches.
SETTLE_START=$(date +%s)
STABLE_SINCE=""
while true; do
    now=$(date +%s)
    if [ $((now - SETTLE_START)) -ge 300 ]; then
        echo "✗ boot-migrate of the HEAD-binary restart did not settle within 300s" >&2
        VM_EXEC bash -c "pgrep -af '[/]sb migrate up' | head -3" >&2 || true
        VM_EXEC bash -c "journalctl --user -u $UNIT --no-pager -n 20 2>/dev/null | grep -E 'applying|migrations' | tail -5" >&2 || true
        exit 1
    fi
    MIG=$(VM_EXEC bash -c "pgrep -f '[/]sb migrate up' 2>/dev/null | head -1" 2>/dev/null | tr -d ' \r\n' || echo "")
    if [ -z "$MIG" ]; then
        if [ -z "$STABLE_SINCE" ]; then STABLE_SINCE=$now; fi
        if [ $((now - STABLE_SINCE)) -ge 10 ]; then break; fi
    else
        STABLE_SINCE=""
    fi
    sleep 2
done
echo "  ✓ unit active on HEAD binary; boot-migrate settled"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — plant the synthetic stall-target migration
#
# Untracked file with timestamp 20991231235959 (beyond any real
# migration): guarantees the post-swap boot-migrate sees ≥1 pending
# migration even when the seed already tracks HEAD's migration level
# (db-seed always tracks HEAD, so the real version-delta may be 0).
# It survives executeUpgrade's `git checkout` (untracked files are
# kept). Delivered via scp — no heredoc-over-ssh (CLAUDE.md rule).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── planting synthetic stall-target migration ──"
scp -O "${SSH_OPTS[@]}" \
    "$LIB_DIR/../fixtures/migration-stall-target.up.sql" \
    root@"$VM_IP":"/home/statbus/statbus/migrations/${SYNTHETIC_MIG}.up.sql"
echo "  synthetic migration written: migrations/${SYNTHETIC_MIG}.up.sql"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — arm the C12 drop-in WITHOUT restarting the unit
#
# daemon-reload does NOT change a running process's environment — the
# drop-in env applies at the NEXT unit start. The next start is the
# exit-42 post-swap restart inside the upgrade flow. So the
# dispatching run (executeUpgrade: backup → checkout → procure → swap)
# is inject-free, and the stall deterministically fires in the
# post-swap boot's boot-migrate child — the STATBUS-012 site.
# (Contrast 3-postswap-watchdog-reconnect, which restarts the unit to
# load its drop-in early: its stall class only fires deep inside
# applyPostSwap, so an early-armed env is safe there. The C12 class
# fires in ANY `sb migrate up` with a pending migration — arming it
# on a running unit that still has to boot-migrate would stall the
# wrong boot.)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── arming C12 drop-in (env lands on the exit-42 post-swap boot) ──"
_dropin_script=$(mktemp /tmp/harness-install-dropin-XXXXXX.sh)
cat > "$_dropin_script" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/statbus-upgrade@statbus.service.d"
DROPIN_FILE="\$DROPIN_DIR/inject.conf"
mkdir -p "\$DROPIN_DIR"
cat > "\$DROPIN_FILE" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_INJECT_AT=migration-slower-than-systemd-unit-timeout
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

UNIT_STATE=$(VM_EXEC systemctl --user is-active "$UNIT" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE" != "active" ]; then
    echo "✗ unit not active after arming the drop-in (state=$UNIT_STATE) — the dispatching unit must keep running" >&2
    VM_EXEC bash -c "systemctl --user status $UNIT --no-pager" >&2 || true
    exit 1
fi
echo "  ✓ drop-in + release file in place; unit still active (env applies on next start)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — fabricate scheduled upgrade row for HEAD
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── fabricating scheduled public.upgrade row for HEAD ──"
# INTENTIONALLY NOT quiesced (fabricate-claim invariant exception): the upgrade
# SERVICE must stay live to dispatch this row and then hit the startup-timeout
# inject on its restart (the unit's drop-in carries STATBUS_INJECT_AT). The
# inject fires on the service's exit-42 restart, not on a `./sb install` run —
# quiescing would prevent the dispatch this scenario exercises.
fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_LOCAL"

ROW_STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$ROW_STATE" != "scheduled" ]; then
    echo "✗ row for HEAD did not reach 'scheduled' state (got '$ROW_STATE')" >&2
    exit 1
fi
echo "  ✓ public.upgrade row at HEAD is state='scheduled'"

NRESTARTS_PRE_DISPATCH=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  pre-dispatch NRestarts: $NRESTARTS_PRE_DISPATCH (diagnostic only — the exit-42 handoff legitimately adds 1)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — wake the service via NOTIFY; wait for the row to be claimed
#
# upgrade_notify_daemon_trigger fires AFTER UPDATE only — a fresh
# INSERT does not NOTIFY, and the poll ticker defaults to 6h. ./sb
# upgrade apply sends NOTIFY upgrade_apply regardless; the service's
# handleNotification → executeScheduled claims the row.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waking service via NOTIFY (./sb upgrade apply $SHORT_SHA) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade apply $SHORT_SHA 2>&1 | tail -5 || true"
echo "  ✓ NOTIFY sent"

echo ""
echo "── waiting for upgrade row to transition to 'in_progress' ──"
START_TS=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge 180 ]; then
        echo "✗ unit did not transition row to in_progress within 180s after NOTIFY" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, started_at FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql" >&2 || true
        VM_EXEC bash -c "systemctl --user status $UNIT --no-pager -l 2>&1 | head -30" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ "$STATE" = "in_progress" ]; then
        echo "  ✓ upgrade row in_progress (t+${elapsed}s) — unit is inside executeUpgrade"
        break
    fi
    sleep 5
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 8 — wait for the stall at the post-swap boot's boot-migrate
#
# Between in_progress and the stall: preswap backup → checkout →
# binary procurement → exit-42 → fresh boot (EnsureDBUp → connect →
# READY=1) → boot-migrate spawns `sb migrate up` → StallHere parks it
# (pre-psql — kills during the hold leave no in-container orphans).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for the boot-migrate stall (post-swap boot) ──"
# Quoting-proof probe: a script file scp'd to the VM (no ssh+sudo+bash
# nested quoting — run-6 proved the shared helper's inline pgrep never
# saw a child that demonstrably existed: the journal recorded TWO
# watchdog kills of the stalled boot-migrate while the helper reported
# nothing for 300s). The probe prints one machine-parsable line. The
# stall site-proof (flag phase) is folded in. Budget 600s: the stretch
# from in_progress to the stall includes the multi-minute preswap
# backup rsync + exit-42 + fresh-boot init (run-6: ~5.5 min — the 300s
# budget expired ~40s before the post-swap boot began, and the exit
# trap then removed the release file, defusing the stall).
_probe_script=$(mktemp /tmp/harness-probe-stall-XXXXXX.sh)
cat > "$_probe_script" << 'PROBE_EOF'
#!/bin/bash
# Stall probe for 3-postswap-migration-timeout. Single line out:
#   PID=<migrate-child-pid-or-empty> REL=<0|1> PHASE=<flag-phase-or-none>
# [/] bracket trick: the pattern does not contain the substring it
# matches, so ssh/sudo/bash wrappers carrying this script's text in
# their cmdline are invisible; the real child
# (/home/statbus/statbus/sb migrate up --verbose) still matches.
REL=0; [ -f /tmp/stall-release-c12 ] && REL=1
PID=$(pgrep -f '[/]sb migrate up' 2>/dev/null | head -1 || true)
PHASE=$(grep -o '"phase": *"[a-z_]*"' "$HOME/statbus/tmp/upgrade-in-progress.json" 2>/dev/null | grep -o '[a-z_]*"$' | tr -d '"' || true)
echo "PID=${PID} REL=${REL} PHASE=${PHASE:-none}"
PROBE_EOF
chmod 644 "$_probe_script"
scp -O "${SSH_OPTS[@]}" "$_probe_script" root@"$VM_IP":/tmp/probe-stall.sh
rm -f "$_probe_script"

MIGRATE_PID=""
STALL_PHASE=""
PROBE_START=$(date +%s)
PROBE_STABLE=""
while true; do
    now=$(date +%s)
    if [ $((now - PROBE_START)) -ge 600 ]; then
        break
    fi
    PROBE_OUT=$(VM_EXEC bash /tmp/probe-stall.sh 2>/dev/null | tail -1 || echo "")
    P_PID=$(echo "$PROBE_OUT" | sed -n 's/.*PID=\([0-9]*\) .*/\1/p')
    P_REL=$(echo "$PROBE_OUT" | sed -n 's/.*REL=\([01]\).*/\1/p')
    P_PHASE=$(echo "$PROBE_OUT" | sed -n 's/.*PHASE=\([a-z_]*\).*/\1/p')
    if [ -n "$P_PID" ] && [ "$P_REL" = "1" ]; then
        if [ -z "$PROBE_STABLE" ]; then
            PROBE_STABLE=$now
            echo "  [probe] migrate child detected (PID=$P_PID, phase=$P_PHASE) — confirming stability"
        elif [ $((now - PROBE_STABLE)) -ge 10 ]; then
            MIGRATE_PID="$P_PID"
            STALL_PHASE="$P_PHASE"
            break
        fi
    else
        if [ -n "$PROBE_STABLE" ]; then
            echo "  [probe] stability broken ($PROBE_OUT) — resetting"
        fi
        PROBE_STABLE=""
    fi
    sleep 3
done
if [ -z "$MIGRATE_PID" ]; then
    echo "✗ stall never activated within 10 min — discriminating diagnostics:" >&2
    echo "── upgrade row (terminal state here = upgrade ran WITHOUT stalling):" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql" >&2 || true
    echo "── flag file (absent = upgrade reached terminal + removed it):" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(no flag file)'" >&2 || true
    echo "── release file (must still exist for a stall to hold):" >&2
    VM_EXEC bash -c "ls -la $RELEASE_FILE 2>/dev/null || echo '(release file MISSING)'" >&2 || true
    echo "── merged unit definition (the drop-in must appear at the bottom):" >&2
    VM_EXEC bash -c "systemctl --user cat $UNIT 2>/dev/null | tail -15" >&2 || true
    echo "── unit state as systemd sees it (Environment must carry the inject vars):" >&2
    VM_EXEC bash -c "systemctl --user show $UNIT -p Environment -p Result -p NRestarts -p ExecMainStartTimestamp 2>/dev/null" >&2 || true
    echo "── journal (post-swap boot? boot-migrate? watchdog?):" >&2
    VM_EXEC bash -c "journalctl --user -u $UNIT --no-pager -n 200 2>/dev/null | grep -iE 'boot-migrate|migrate|Started|Stopping|Stopped|watchdog|Handing off|Detected|Resuming|rolled' | tail -40" >&2 || true
    exit 1
fi
echo "  migrate subprocess PID=$MIGRATE_PID parked in StallHere"

# LOAD-BEARING site check: the flag must be Phase=post_swap while the
# stall holds — proving the stalled migrate is the POST-SWAP BOOT's
# boot-migrate (pre-recoverFromFlag), i.e. the STATBUS-012 site, not
# some other migrate invocation. The probe carried the phase out with
# the PID, sampled in the SAME probe round — no separate read needed.
if [ "$STALL_PHASE" != "post_swap" ]; then
    echo "✗ stall is active but the upgrade flag phase is '$STALL_PHASE', not post_swap — wrong site" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(no flag file)'" >&2 || true
    exit 1
fi
echo "  ✓ flag is post_swap during the stall — this IS the post-swap boot's boot-migrate"

# ─────────────────────────────────────────────────────────────────────────
# Phase 9 — post-stall baseline, then hold past WatchdogSec
# ─────────────────────────────────────────────────────────────────────────
NRESTARTS_STALL=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo ""
echo "── post-stall NRestarts baseline: $NRESTARTS_STALL — holding ${STALL_HOLD_S}s (> WatchdogSec=120s) ──"
# During this hold the service main goroutine is parked in
# runCommandToLog waiting on the stalled migrate child. The
# STATBUS-012 fix's always-ping ticker must emit WATCHDOG=1 every 30s
# for the unit to survive. Without it: SIGABRT at ~READY+120s,
# Restart=always re-boots, the stall re-arms, NRestarts climbs.
sleep "$STALL_HOLD_S"

# ─────────────────────────────────────────────────────────────────────────
# Phase 10 — LOAD-BEARING: no watchdog kill during the stall
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── STATBUS-012 regression check (LOAD-BEARING) ──"
NRESTARTS_AFTER_HOLD=$(VM_EXEC systemctl --user show "$UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
UNIT_RESULT=$(VM_EXEC systemctl --user show "$UNIT" --property=Result --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESTART_DELTA=$((NRESTARTS_AFTER_HOLD - NRESTARTS_STALL))
echo "  NRestarts: post-stall=$NRESTARTS_STALL after-hold=$NRESTARTS_AFTER_HOLD delta=$RESTART_DELTA"
echo "  unit Result: $UNIT_RESULT"

if [ "$RESTART_DELTA" -gt 0 ] || [ "$UNIT_RESULT" = "watchdog" ]; then
    echo "✗ watchdog killed the unit during the boot-migrate stall — STATBUS-012 gap is live" >&2
    echo "  boot-migrate ran >WatchdogSec(120s) with no WATCHDOG=1 source: the idle heartbeat" >&2
    echo "  ticker does not exist yet at service.go:1644 and no always-ping ticker covers the" >&2
    echo "  migrate subprocess. Expected fix: runGatedWatchdogTicker(nil progress) around" >&2
    echo "  boot-migrate-up + shared 30-min migrate timeout (doc-005)." >&2
    echo "" >&2
    echo "  watchdog evidence from the journal:" >&2
    VM_EXEC bash -c "journalctl --user -u $UNIT --no-pager -n 200 2>/dev/null | grep -iE 'watchdog|SIGABRT|Failed with result' | tail -10" >&2 || true
    echo "  flag state:" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null" >&2 || true
    echo "  upgrade row:" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql" >&2 || true
    exit 1
fi
echo "  ✓ no watchdog kill across ${STALL_HOLD_S}s stall — boot-migrate watchdog cover holds"

# ─────────────────────────────────────────────────────────────────────────
# Phase 11 — release the stall; upgrade must run to completion
#
# boot-migrate finishes the delta (incl. the synthetic migration) →
# recoverFromFlag → resumePostSwap → applyPostSwap (its migrate is a
# no-op — boot-migrate already brought the schema to HEAD) → completed.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── removing release file; migration should proceed to completion ──"
remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE"

START_TS=$(date +%s)
FINAL_STATE=""
while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$UPGRADE_BUDGET_S" ]; then
        echo "✗ upgrade did not reach terminal state within ${UPGRADE_BUDGET_S}s after release" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql" >&2 || true
        VM_EXEC bash -c "journalctl --user -u $UNIT --no-pager -n 40" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    case "$STATE" in
        completed|failed|rolled_back)
            FINAL_STATE="$STATE"
            echo "  ✓ upgrade reached state='$STATE' (t+${elapsed}s after release)"
            break
            ;;
    esac
    sleep 5
done

if [ "$FINAL_STATE" != "completed" ]; then
    echo "✗ expected state='completed' after releasing the stall, got '$FINAL_STATE'" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$HEAD_LOCAL';\" | ./sb psql" >&2 || true
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 12 — assertions
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── final assertions ──"

# Data integrity — the stall + completion must not touch user data.
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

# Coherence.
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
# Whole-scenario restart bound: exactly 1 legitimate restart (the
# exit-42 handoff); tolerance 2 leaves headroom for a transient.
assert_systemd_restart_counter_bounded "$VM_NAME" "$UNIT" 2

assert_health_passes "$VM_NAME"

echo ""
echo "PASS: 3-postswap-migration-timeout (boot-migrate survived a ${STALL_HOLD_S}s stalled migration under WatchdogSec=120s — STATBUS-012 cover holds)"
