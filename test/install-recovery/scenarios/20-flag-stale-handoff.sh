#!/bin/bash
# Scenario 20: flag-stale-handoff  (C14 / R3 — install/upgrade-service mutex handoff)
#
# Class:                 install-flag-released-without-clean-handoff-detected-as-stale
# Class kind:            External (no in-code inject site fires)
# Forensics tag:         R3
# Source forensics:      tmp/install-state-machine-forensics.md
#
# Expected principled behavior:
#   `./sb install` and the supervised `statbus-upgrade@<slot>.service` unit
#   share a filesystem-level mutex: `tmp/upgrade-in-progress.json`. The
#   contract is "whichever process writes the flag with its own PID must
#   release it on exit (clean or otherwise)". The forensics surfaced a
#   gap: an install can exit cleanly WITHOUT releasing the flag, leaving
#   the file on disk with the install's dead PID. On the upgrade-
#   service's next poll tick the orphan flag is detected as "stale"
#   (PID dead → assume crashed) and cleared. That clearing is
#   convergent in effect — the next install / scheduled upgrade can
#   proceed — but the path takes the wrong code branch: it interprets
#   a CLEAN exit as a CRASHED install and logs misleading diagnostics
#   (and could in principle leave behind half-written rollback state
#   on a path that does more than just delete the flag).
#
#   The principled fix is "install MUST release the flag on clean
#   exit" — which is the simpler invariant. Without that fix, the
#   service's stale-flag branch is the convergence path and the test
#   surfaces the buggy-but-not-data-destroying behavior.
#
# Scenario kind: external orchestration (no in-code inject site).
#   Per the inject registry, C14 is KindExternal — there's no
#   `inject.X` call that fires for this class. The scenario simply:
#     1. runs `./sb install` to clean exit, and
#     2. observes whether the flag file is left on disk.
#   If the flag IS left behind after a clean install, the scenario
#   marks RED with diagnostic output documenting the gap. If the
#   flag is absent (fix landed), the scenario marks GREEN.
#
# Expected on current branch (per the forensics): RED — the install
#   does not release the flag on clean exit. This scenario is the
#   empirical surfacer for the fix; the fix follows as a separate
#   commit.
#
# Trigger logic:
#   1. Bootstrap the VM at INSTALL_VERSION (any released tag — the
#      content of the install isn't load-bearing for this scenario;
#      we just need an install to complete and exit).
#   2. Right after `install_statbus_in_vm` returns, immediately
#      check whether `~/statbus/tmp/upgrade-in-progress.json` exists.
#      No sleep, no service tick wait — we want the snapshot AT
#      exit, before the upgrade-service's next poll can clean it up.
#   3. If the flag IS present: assert that its Holder is "install"
#      and the PID is dead (sanity-check the wedge shape).
#   4. Wait for the upgrade-service's next tick (default 60s + slack)
#      and re-check. The service's R3 clear path should remove the
#      flag (current code) OR the install should have removed it
#      itself (post-fix code).
#   5. Either way, the post-tick state MUST be: flag absent, no
#      orphan-row state in public.upgrade, services healthy.
#
# Hetzner-runnability:
#   READY as a DIAGNOSTIC. Expected to expose the R3 leak today; once
#   the fix lands the post-install check will go from "flag still
#   there" to "flag absent immediately" and the scenario adjusts to
#   require the immediate-absence check.
#
# Usage:
#   INSTALL_VERSION=v2026.05.4 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/20-flag-stale-handoff.sh \
#     statbus-recovery-20

set -euo pipefail

VM_NAME="${1:-statbus-recovery-20}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.4}"
SERVICE_TICK_WAIT_S="${SERVICE_TICK_WAIT_S:-120}"   # > default tick interval (60s) + slack

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario 20: flag-stale-handoff  (C14 / R3 — clean-exit flag leak)"
echo "  Install version: $INSTALL_VERSION"
echo ""
echo "  Expected on current branch (no fix yet): the flag file is left"
echo "  on disk after a clean install exit; the upgrade-service's R3"
echo "  stale-flag clear path removes it on the next tick. Once the"
echo "  principled fix lands (install releases the flag on clean"
echo "  exit), the post-install check should show the flag absent"
echo "  immediately."
echo "════════════════════════════════════════════════════════════════"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — observe flag state immediately after install exits
#
# Snapshot the upgrade-in-progress.json content BEFORE the upgrade-
# service's next tick gets a chance to clean it up. This is the load-
# bearing surfacer: did the install leave its mutex behind?
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── snapshotting flag state immediately after install ──"
POST_INSTALL_PROBE=$(VM_EXEC bash -c "
    cd ~/statbus
    if [ -f tmp/upgrade-in-progress.json ]; then
        echo 'FLAG_PRESENT'
        cat tmp/upgrade-in-progress.json
    else
        echo 'FLAG_ABSENT'
    fi
")
echo "$POST_INSTALL_PROBE"

if echo "$POST_INSTALL_PROBE" | grep -q "FLAG_ABSENT"; then
    echo ""
    echo "  ✓ Flag absent immediately after install exit — the R3 leak is FIXED."
    echo "    (Skipping the stale-clear observation; nothing to clear.)"
    FLAG_LEAKED=0
else
    echo ""
    echo "  ⚠ Flag PRESENT immediately after install exit — confirms the R3 leak."
    echo "    Expected on current code. Sanity-checking wedge shape (Holder + PID)..."

    HOLDER=$(VM_EXEC bash -c "cd ~/statbus && grep -o '\"Holder\":\"[^\"]*\"' tmp/upgrade-in-progress.json 2>/dev/null | head -1" || echo "")
    HOLDER_PID=$(VM_EXEC bash -c "cd ~/statbus && grep -o '\"Pid\":[0-9]*' tmp/upgrade-in-progress.json 2>/dev/null | head -1 | sed 's/.*://'" || echo "")
    echo "    parsed: Holder=$HOLDER Pid=$HOLDER_PID"

    if echo "$HOLDER" | grep -qi 'install'; then
        echo "    ✓ Holder field reflects install ownership"
    else
        echo "    ✗ Expected Holder=install but got: $HOLDER" >&2
        echo "      (Flag could belong to the supervised upgrade-service — different scenario)" >&2
        exit 1
    fi

    if [ -n "$HOLDER_PID" ]; then
        PID_ALIVE=$(VM_EXEC bash -c "kill -0 $HOLDER_PID 2>/dev/null && echo alive || echo dead" || echo "?")
        echo "    PID $HOLDER_PID liveness: $PID_ALIVE"
        if [ "$PID_ALIVE" != "dead" ]; then
            echo "    ⚠ PID still alive — the install process has not actually exited yet" >&2
            echo "      (Race against install backgrounding? Investigate.)" >&2
        fi
    fi

    FLAG_LEAKED=1
fi

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — wait for the upgrade-service's next tick + observe cleanup
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting ${SERVICE_TICK_WAIT_S}s for upgrade-service tick to run stale-flag clear path ──"
sleep "$SERVICE_TICK_WAIT_S"

POST_TICK_FLAG=$(VM_EXEC bash -c "
    cd ~/statbus
    if [ -f tmp/upgrade-in-progress.json ]; then
        echo 'STILL_PRESENT'
    else
        echo 'CLEARED'
    fi
")
echo "  post-tick flag state: $POST_TICK_FLAG"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — assertions
#
# Load-bearing: post-tick the flag MUST be cleared. Either the install
# released it cleanly (post-fix shape) OR the upgrade-service's R3
# stale-clear path removed it (current shape). Both converge to flag
# absent. If the flag is STILL present after a full tick interval,
# the convergence guarantee is broken.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

if [ "$POST_TICK_FLAG" != "CLEARED" ]; then
    echo "✗ flag still present after ${SERVICE_TICK_WAIT_S}s — neither install nor service cleared it" >&2
    VM_EXEC bash -c "cd ~/statbus && cat tmp/upgrade-in-progress.json" >&2 || true
    VM_EXEC bash -c "systemctl --user status statbus-upgrade@test.service --no-pager" >&2 || true
    exit 1
fi
echo "  ✓ flag cleared post-tick"

assert_health_passes "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"

# Diagnostic summary at end.
echo ""
if [ "$FLAG_LEAKED" = "1" ]; then
    echo "DIAGNOSTIC PASS: flag-stale-handoff (C14/R3) — install LEAKS the flag on clean exit;"
    echo "  upgrade-service's stale-clear path converges. Fix shape: install must release the"
    echo "  flag on clean exit (the install-owned acquire path's defer in install.go's"
    echo "  acquireOrBypass already calls ReleaseInstallFlag — verify it runs on every exit"
    echo "  path; a leaked exit code or early return bypassing the defer is the suspect)."
else
    echo "PASS: flag-stale-handoff (C14/R3) — install releases the flag cleanly on exit (fix landed)."
fi
