#!/bin/bash
# Scenario: 0-happy-upgrade  (baseline — no failure injection)
# judge = <baseline release binary>, judged = <tagged candidate>
# Shape: standalone + prerelease by default, matching rune and the Norway hop.
# Optional failure axis: HARNESS_PRESWAP_FETCH_ERROR=1 adds
# STATBUS_INJECT_AT=preswap-fetch-returns-error to the upgrade service unit, so
# the real preswap fetch returns an error rather than killing the process.
#
# Class:                 N/A (baseline regression net for the happy path)
# Class kind:            N/A — no inject site fires
# Source forensics:      tmp/install-state-machine-forensics.md
#                        (the implicit complement to every failure scenario)
#
# Expected principled behavior:
#   The supervised, unattended upgrade path — install at an older
#   release → populate data → schedule upgrade to a tagged candidate → wait for
#   the upgrade-service unit's poll tick to dispatch + run
#   executeUpgrade → applyPostSwap to completion — must converge
#   to a healthy state with data intact. This is the BASELINE
#   regression net that catches any change that makes the normal
#   upgrade path break, independent of any failure-injection
#   scenario.
#
#   The unattended path differs from the inline `./sb install` path
#   used by scenarios 12+/15+/16+/17+/21+/22+/23+/24 in one
#   important way: the upgrade-service systemd unit dispatches the
#   upgrade against the supervised WatchdogSec + TimeoutStopSec
#   budgets. A regression in the unit's notify-protocol wiring
#   (e.g., a missed WATCHDOG=1 or READY=1) would show up here
#   first, even if the inline tests are all green.
#
# Trigger logic:
#   1. Require INSTALL_TARGET_TAG or select a release-shaped tag at HEAD.
#      An untagged HEAD refuses because this cross-version proof needs a tag.
#   2. Install the newest release baseline below that target via install.sh.
#   3. Populate demo data and snapshot counts. The installed release binary stays
#      in place: it is the judge, and the tagged candidate is the judged target.
#   4. Register and schedule INSTALL_TARGET_TAG through the released binary.
#   5. Wait for the supervised service to complete the real upgrade hop.
#   6. Assert data, health, completion, and bounded restarts.
#
# Hetzner-runnability:
#   READY. No injection site needed. This is the baseline that all
#   other scenarios assume holds — if it fails, the upgrade-service's
#   notify protocol or the inline-vs-supervised dispatch path has
#   diverged.
#
# Usage:
#   INSTALL_VERSION=v2026.08.0 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/0-happy-upgrade.sh \
#     statbus-recovery-0-happy-upgrade

set -euo pipefail

VM_NAME="${1:-statbus-recovery-0-happy-upgrade}"
HARNESS_DEPLOYMENT_MODE="${HARNESS_DEPLOYMENT_MODE:-standalone}"
HARNESS_UPGRADE_CHANNEL="${HARNESS_UPGRADE_CHANNEL:-prerelease}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-900}"
# > tick interval (60s) + slack, times enough ticks to ride out a registry
# transient: verifyArtifacts retries every discovery cycle, so a ghcr 401/500
# storm costs WAITING lines here, not a red run (rc.05 died at 90s with
# last='building' while the storm was still active and all four images existed).
# Cold-start sized: rc.08's forensics proved the mechanism sound (all four
# images inspect OK from the VM) while the row stayed 'building' — a fresh
# box's FIRST verify pass grinds the entire discovered tag backlog (a pass
# that starts before our register cannot see our row; only a later pass
# flips it). 600s expired inside that first pass. 1500s covers the observed
# cold-start cost; liveness lines every 30s keep the wait visibly alive.
TICK_WAIT_S="${TICK_WAIT_S:-1500}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
# An explicit environment pin wins. The default is computed at run time so
# this smoke never fossilises around an archaeological release.
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
if [ -z "${INSTALL_TARGET_TAG:-}" ]; then
    if [ -z "$TARGET_TAGS" ]; then
        echo "ERROR: 0-happy-upgrade cross-version proof needs a release-shaped tag at HEAD; local runs may pass INSTALL_TARGET_TAG explicitly" >&2
        exit 1
    fi
    INSTALL_TARGET_TAG=$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)
fi
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null || {
    echo "ERROR: INSTALL_TARGET_TAG '$INSTALL_TARGET_TAG' is not a release-shaped stable/RC tag" >&2
    exit 1
}
TARGET_SHA=$(git -C "$REPO_ROOT" rev-list -1 "$INSTALL_TARGET_TAG" 2>/dev/null) || {
    echo "ERROR: INSTALL_TARGET_TAG '$INSTALL_TARGET_TAG' is not present in the repository" >&2
    exit 1
}
HEAD_LOCAL=$(git -C "$REPO_ROOT" rev-parse HEAD)
if [ "$TARGET_SHA" != "$HEAD_LOCAL" ]; then
    echo "ERROR: INSTALL_TARGET_TAG '$INSTALL_TARGET_TAG' does not point at HEAD; cross-version proof must judge the candidate at HEAD" >&2
    exit 1
fi
INSTALL_VERSION="${INSTALL_VERSION:-$(select_release_baseline_from_repo "$REPO_ROOT" "$INSTALL_TARGET_TAG")}"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 0-happy-upgrade  (baseline — supervised unattended path)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: $INSTALL_TARGET_TAG"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA="$TARGET_SHA"
echo "  Tagged target: $INSTALL_TARGET_TAG ($HEAD_SHA)"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

echo ""
echo "── initial install at $INSTALL_VERSION ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-upgrade data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

if [ "${HARNESS_PRESWAP_FETCH_ERROR:-}" = "1" ]; then
    echo ""
    echo "── arming returned preswap fetch error on the upgrade service ──"
    VM_EXEC bash -c 'mkdir -p "$HOME/.config/systemd/user/statbus-upgrade@statbus.service.d" && cat > "$HOME/.config/systemd/user/statbus-upgrade@statbus.service.d/preswap-fetch-error.conf" <<EOF
[Service]
Environment=STATBUS_INJECT_AT=preswap-fetch-returns-error
EOF
systemctl --user daemon-reload
systemctl --user restart statbus-upgrade@statbus.service'
    echo "  ✓ preswap fetch error injection armed"
fi

# Verify upgrade-service unit is active before we start.
UNIT_STATE_BEFORE=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
if [ "$UNIT_STATE_BEFORE" != "active" ]; then
    echo "✗ upgrade-service unit not active before upgrade trigger (state=$UNIT_STATE_BEFORE)" >&2
    exit 1
fi
echo "  ✓ upgrade-service active before trigger"

NRESTARTS_BASELINE=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "0")
echo "  baseline NRestarts: $NRESTARTS_BASELINE"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — keep the installed release binary in place
#
# judge = the baseline release binary installed by install.sh.
# judged = the tagged candidate at HEAD. No upload_sb_to_vm or checkout occurs:
# the released daemon performs the genuine preswap fetch, verification, and swap.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── keeping $INSTALL_VERSION binary as judge of $INSTALL_TARGET_TAG ──"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — REGISTER the tagged candidate (the real post-086 path)
#
# The installed release binary drives register → ready → schedule. The target is
# a release-shaped tag, matching the operator and Norway prerelease hop.
# INTENTIONALLY NOT quiesced: the supervised upgrade service claims the row.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── registering $INSTALL_TARGET_TAG as an upgrade candidate ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $INSTALL_TARGET_TAG 2>&1 | tail -20"

echo ""
echo "── waiting for the candidate to reach 'ready' (register → ready) ──"
wait_for_upgrade_candidate_ready "$VM_NAME" "$HEAD_SHA" "$TICK_WAIT_S"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — SCHEDULE the ready candidate (./sb upgrade schedule)
#
# Promotes the row to 'scheduled'; upgrade_notify_daemon_trigger fires NOTIFY
# upgrade_apply; the running (unquiesced) upgrade-service unit claims it and runs
# executeUpgrade → applyPostSwap. This is the genuine
# register→ready→schedule→service-runs→completed real path (criterion-8).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── scheduling the upgrade (./sb upgrade schedule) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $INSTALL_TARGET_TAG 2>&1 | tail -20"

# Wait for the row to transition to in_progress, then to a terminal state.
echo ""
echo "── waiting for upgrade to reach in_progress, then terminal state ──"
START_TS=$(date +%s)
SAW_IN_PROGRESS=0
FINAL_STATE=""

while true; do
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$UPGRADE_BUDGET_S" ]; then
        echo "✗ upgrade did not reach terminal state within ${UPGRADE_BUDGET_S}s" >&2
        VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, commit_sha, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
        exit 1
    fi
    STATE=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$HEAD_SHA' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    case "$STATE" in
        in_progress)
            if [ "$SAW_IN_PROGRESS" = "0" ]; then
                echo "  ✓ upgrade in_progress (t+${elapsed}s)"
                SAW_IN_PROGRESS=1
            fi
            ;;
        completed|failed|rolled_back)
            FINAL_STATE="$STATE"
            echo "  ✓ upgrade reached state='$STATE' (t+${elapsed}s)"
            break
            ;;
    esac
    if [ $((elapsed % 30)) -eq 0 ] && [ "$elapsed" -gt 0 ]; then
        echo "    [t+${elapsed}s] state=$STATE"
    fi
    sleep 5
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — assertions
#
# Happy path: state MUST be 'completed'. Anything else is a regression.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── convergence checks ──"

if [ "$FINAL_STATE" != "completed" ]; then
    echo "✗ happy-upgrade did NOT reach state='completed' (got '$FINAL_STATE')" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$HEAD_SHA' ORDER BY id DESC LIMIT 3;\" | ./sb psql" >&2 || true
    exit 1
fi
echo "  ✓ state='completed'"

assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"

# Bounded restarts. The normal upgrade should NOT have triggered any
# watchdog or start-timeout — NRestarts ought to stay at baseline.
NRESTARTS_FINAL=$(VM_EXEC systemctl --user show "statbus-upgrade@statbus.service" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?")
RESTART_DELTA=$((NRESTARTS_FINAL - NRESTARTS_BASELINE))
echo "  NRestarts: baseline=$NRESTARTS_BASELINE final=$NRESTARTS_FINAL delta=$RESTART_DELTA"
if [ "$RESTART_DELTA" -gt 2 ]; then
    echo "✗ NRestarts grew by $RESTART_DELTA during a happy upgrade — unit was unstable" >&2
    exit 1
fi
echo "  ✓ restart counter bounded"

echo ""
echo "PASS: 0-happy-upgrade (supervised unattended path completed cleanly; data intact; unit stable)"
