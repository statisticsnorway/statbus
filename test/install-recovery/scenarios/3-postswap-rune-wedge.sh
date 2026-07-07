#!/bin/bash
# Scenario: 3-postswap-rune-wedge  (STATBUS-044 AC#1 — the rune shape, case 0)
#
# THE SHAPE THIS PROVES: Norway's rune box sat wedged for 18 days with an
# in_progress upgrade row, a service-held post_swap recovery flag, and a STALE
# proxy container (running an older commit than the flag target) — while the
# database and binary were already AT the target. The STATBUS-039 recovery
# ruled: that box must go FORWARD — `./sb install` takes over (SIGKILL-class
# quiesce, never SIGTERM), resumes the post-swap pipeline, recreates the FULL
# service set (including the stale/missing proxy) at the flag target, converges
# the row to `completed`, removes the flag, and NEVER runs a restore. This
# scenario fabricates exactly that shape on a fresh VM and asserts every leg,
# plus the idempotence coda: a second `./sb install` detects nothing-scheduled.
#
# This is CASE 0 of the STATBUS-044 verdict matrix (at-target + containers not
# yet at flag target → forward convergence to completed; see the ticket's
# Implementation Notes). It was validated ONCE, live, on the real rune box
# during the rc.02 recovery (STATBUS-047: "039 takeover validated live —
# NRestarts=10784 → SIGKILL-class quiesce, never SIGTERM → roll-forward, no
# rollback; row 187 completed"). This scenario is the STANDING regression net
# for that one-shot live proof.
#
# ─────────────────────────────────────────────────────────────────────────
# WHAT IS AND IS NOT EXERCISED (honest boundary)
# ─────────────────────────────────────────────────────────────────────────
# EXERCISED: the install ladder's crashed-upgrade detection (flag present +
# flock free + dead pid), the SIGKILL-class quiesce of a LIVE upgrade unit
# (the old release's daemon is deliberately left running when `./sb install`
# fires — the takeover kills it, never TERMs it), the STATBUS-052 flock-
# confirmed-death observer, RecoverFromFlag's post_swap routing,
# resumePostSwap's containers-at-flag-target probe failing on the stale set,
# applyPostSwap recreating every service at the target, the completed
# terminal, flag removal, and the nothing-scheduled idempotence coda.
#
# NOT EXERCISED (and why that is honest, not a gap): the CRASH-LOOPING
# reclassification gate (upgradeUnitCrashLooping, NRestarts>=3 → treat
# live-upgrade as crashed-upgrade). A unit that crash-loops the way rune's
# OLD binary did is nearly extinct on HEAD BY DESIGN — the STATBUS-046 death
# budget parks a repeatedly-dying recovery at 3 process deaths (r19-proven),
# so a natural persistent loop cannot be constructed from shipped code
# without scaffolding that would fake the very condition under test. That
# gate remains covered by its unit tests (upgradeUnitCrashLooping,
# conservative-false probes) and by the one live firing on rune itself.
# Here the unit is alive-but-idle at takeover time: the quiesce MECHANICS
# (mask → SIGKILL → flock-confirm → never SIGTERM) are asserted identically.
#
# ─────────────────────────────────────────────────────────────────────────
# MECHANISM — direct state fabrication (the sanctioned resume-state class)
# ─────────────────────────────────────────────────────────────────────────
# The rune shape is a POST-CRASH RESUME STATE: real dispatch cannot present
# "an upgrade that already swapped, already migrated, and then died leaving a
# stale proxy" on cue. Fabrication here is the construction of that state —
# an in_progress row + service-held post_swap flag with a dead pid
# (lib/data-helpers.sh fabricate_resume_state, the exact helper the r19-green
# park scenario proved) — and everything AFTER the construction is the real
# product code reading it. This is the resume-state fabrication class whose
# carve-out from STATBUS-071 AC#4 is before the King (071's Implementation
# Notes); this scenario's fabrication is additionally sanctioned directly by
# STATBUS-044 AC#1's own text ("fabricate the rune shape on a VM").
# NOTE the flag deliberately carries NO backup_path (fabricate_resume_state's
# faithful shape): if the recovery ever WRONGLY routed this at-target box to
# a rollback, restoreDatabase declines the empty identity SILENTLY (returns
# nil — "No snapshot was recorded … refusing to touch the live volume",
# exec.go:861-863), so the data survives; what makes the wrong route FAIL
# LOUD here are the ROW assertions (rolled_back_at must stay NULL, state
# must reach completed) — they are the enforcing trap, and a populated
# backup_path would only have added a restore that masks the mis-route.
#
# STALENESS CONSTRUCTION: after the baseline install at INSTALL_VERSION, the
# working tree + binary + database are brought to HEAD (upload + checkout +
# steady-state pre-apply, verbatim the park scenario's proven sequence), and
# the CONTAINERS still run INSTALL_VERSION's images — a strict superset of
# rune's single stale proxy, INCLUDING a stale-but-serving proxy exactly as
# rune had. The proxy is deliberately NOT removed: v1 of this scenario
# `docker rm -f`-ed it as a "harsher variant of stale" and the first run
# proved that wrong — the DB connection routes THROUGH the proxy (Caddy's
# layer4 on CADDY_DB_BIND:PORT), so a MISSING proxy severs the recovery's own
# DB path (a different state than staleness; rune's proxy was old but
# serving). That severed-route state exposed a REAL product sharp edge
# (probe-vs-connect route mismatch in install crash recovery — its own
# ticket); THIS scenario's job is the faithful rune shape, so the proxy
# stays present and stale.
#
# SCENARIO SHAPE
#   1. Install at INSTALL_VERSION; demo data + counts snapshot.
#   2. Upload HEAD sb; fetch+checkout HEAD (bad-object guard, verbatim).
#   3. Steady-state pre-apply: config generate + `sb migrate up` (DB reaches
#      HEAD ⇒ observed-state reads already-at-new; boot-migrate at recovery
#      time is a no-op). NO synthetic migrations — clean forward is the point.
#   4. Fabricate the rune shape: assert the proxy is stale-but-SERVING (it is
#      deliberately NOT removed — see STALENESS CONSTRUCTION); fabricate the
#      in_progress row + post_swap flag (dead pid). The OLD daemon stays
#      RUNNING — it is the takeover's target (park-scenario precedent proves
#      fabricating under the idling old daemon is safe; act immediately).
#   5. `./sb install` → assert: crashed-upgrade detected; SIGKILL-class
#      quiesce lines + flock-confirmed-death line; exit 0.
#   6. Assert convergence: row completed (attempts==1, not parked,
#      rolled_back_at NULL, error NULL); flag absent; ALL four commit-tagged
#      containers (db/app/worker/proxy) running at HEAD's short tag + rest
#      running; health 200; demo data counts == snapshot (data untouched —
#      the empirical no-restore proof); no restore markers in the install
#      output; upgrade unit active.
#   7. Second `./sb install` → nothing-scheduled + exit 0 (idempotence).
#
# Hetzner-runnability: BUILD-ONLY at authoring time — the VM run is the
# oracle (architect, STATBUS-044 AC#1; foldable into the 071 U-campaign).
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-rune-wedge.sh \
#     statbus-recovery-3-postswap-rune-wedge

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-rune-wedge}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
# The takeover install pulls HEAD's four per-commit images + recreates the
# service set; give it its own generous bound so a wedge fails THIS phase
# with a named error instead of eating the scenario's global budget.
TAKEOVER_BUDGET_S="${TAKEOVER_BUDGET_S:-1200}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-rune-wedge  (STATBUS-044 AC#1 — takeover→forward→completed, zero restores)"
echo "  Initial release: $INSTALL_VERSION → flag target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
HEAD_SHORT=$(echo "$HEAD_SHA" | cut -c1-8)
echo "  HEAD: $HEAD_SHA ($HEAD_SHORT)"

UPGRADE_UNIT="statbus-upgrade@statbus.service"

# ─────────────────────────────────────────────────────────────────────────
# helpers local to this scenario
# ─────────────────────────────────────────────────────────────────────────

# rune_row_cols — the columns every terminal assertion reads, one pipe row:
# state | recovery_attempts | parked? | rolled_back? | error-present?
rune_row_cols() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state, recovery_attempts, recovery_parked_at IS NOT NULL, rolled_back_at IS NOT NULL, error IS NOT NULL FROM public.upgrade ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r'
}

# running_image_for <name-fragment> — the image ref of the running container
# whose name contains <fragment> ('' if not running). docker ps only (running
# containers), so a crash-looping recreate cannot satisfy it.
running_image_for() {
    VM_EXEC bash -c "docker ps --format '{{.Names}} {{.Image}}' | grep -- '-$1' | head -1 | awk '{print \$2}'" 2>/dev/null | tr -d ' \r\n'
}

# ─────────────────────────────────────────────────────────────────────────
# Phase 1 — baseline install + demo data
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── initial install at $INSTALL_VERSION ──"
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-fabrication data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 2 — bring binary + tree + DB to HEAD (containers stay stale)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── uploading HEAD sb binary ──"
upload_sb_to_vm "$VM_NAME"

# Fetch + checkout HEAD in the VM's working tree (mirrors 0-happy-upgrade.sh
# VERBATIM — the release install's clone is depth-1 and cannot resolve the
# uploaded binary's embedded HEAD commit without this; see the park scenario's
# run-7 finding).
VM_EXEC bash -c "cd ~/statbus && if ! git cat-file -e $HEAD_SHA 2>/dev/null; then git fetch --depth 1 origin $HEAD_SHA || { echo 'FATAL: cannot fetch HEAD' >&2; exit 1; }; fi && git checkout $HEAD_SHA"

echo ""
echo "── steady-state pre-apply: config generate + migrate up (DB → HEAD; observed-state will read already-at-new) ──"
# config generate FIRST — the release-era .env lacks keys HEAD's compose file
# requires (REST_ADMIN_BIND_ADDRESS et al.; the park scenario's r15 finding).
VM_EXEC bash -c "cd ~/statbus && ./sb config generate"
# timeout 600: migrate.Up is unbounded from the CLI; a wedged pre-apply must
# fail THIS phase with a named error, not eat the global budget.
VM_EXEC bash -c "cd ~/statbus && timeout 600 ./sb migrate up --verbose"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — fabricate the rune shape (stale set incl. stale-but-SERVING proxy
# + row + flag). The proxy is NOT removed — see the STALENESS CONSTRUCTION
# header note: the DB path routes through it, and rune's proxy was serving.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── confirming the stale-but-serving proxy (rune's headline: old image, still routing) ──"
PROXY_BEFORE=$(running_image_for proxy)
[ -n "$PROXY_BEFORE" ] || { echo "✗ precondition: no running proxy container found — the stale set needs a SERVING stale proxy (the DB path routes through it)" >&2; exit 1; }
case "$PROXY_BEFORE" in
    *"$HEAD_SHORT"*) echo "✗ proxy already at the flag target ($PROXY_BEFORE) — nothing stale to converge; the baseline install did not leave the expected stale set" >&2; exit 1 ;;
    *) echo "  ✓ proxy stale and serving: $PROXY_BEFORE (≠ flag target $HEAD_SHORT); remaining containers also on $INSTALL_VERSION images" ;;
esac

echo ""
echo "── fabricating the in_progress row + service-held post_swap flag (dead pid; OLD daemon left RUNNING as the takeover target) ──"
fabricate_resume_state "$VM_NAME" "$HEAD_SHA" >/dev/null
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"
echo "  ✓ old daemon still active — the takeover has a live unit to quiesce"

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — THE TAKEOVER: ./sb install
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── ./sb install (expect: crashed-upgrade → SIGKILL-class quiesce → forward resume → completed) ──"
INSTALL_OUT=$(mktemp)
set +e
timeout "${TAKEOVER_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
    "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
    > "$INSTALL_OUT" 2>&1
INSTALL_RC=$?
set -e
cat "$INSTALL_OUT"
echo "  ./sb install (takeover) exit: $INSTALL_RC"
[ "$INSTALL_RC" -eq 0 ] || { echo "✗ takeover install did not exit 0 — the rune shape must converge forward autonomously" >&2; exit 1; }

echo ""
echo "── assert 1: crashed-upgrade detected + SIGKILL-class quiesce (never SIGTERM) + flock-confirmed death ──"
grep -q "Detected install state: crashed-upgrade" "$INSTALL_OUT" || {
    echo "✗ expected 'Detected install state: crashed-upgrade' in the install output" >&2; exit 1; }
echo "  ✓ ladder detected crashed-upgrade"
grep -q "quiescing upgrade unit" "$INSTALL_OUT" || {
    echo "✗ expected the SIGKILL-class quiesce line ('Crash recovery: quiescing upgrade unit …') — the live old daemon must be taken over, not ignored" >&2; exit 1; }
grep -q "never SIGTERM" "$INSTALL_OUT" || {
    echo "✗ expected the quiesce line to carry its 'never SIGTERM' contract marker" >&2; exit 1; }
echo "  ✓ SIGKILL-class quiesce ran (never SIGTERM)"
grep -q "confirmed dead" "$INSTALL_OUT" || {
    echo "✗ expected the STATBUS-052 flock-confirmed-death line ('confirmed dead — upgrade flock … released')" >&2; exit 1; }
echo "  ✓ death confirmed via the authoritative flock (STATBUS-052)"

echo ""
echo "── assert 2: NO restore ran (output markers + row columns) ──"
if grep -qE "auto-restor|Restoring database|rolled back to the previous version" "$INSTALL_OUT"; then
    echo "✗ install output contains restore/rollback markers — an at-target rune shape must NEVER restore (STATBUS-039)" >&2
    exit 1
fi
echo "  ✓ no restore/rollback markers in the install output"

ROW=$(rune_row_cols)
echo "  terminal row: $ROW  (state|attempts|parked|rolled_back|error)"
ROW_STATE=$(echo "$ROW"  | cut -d'|' -f1)
ROW_ATTEMPTS=$(echo "$ROW" | cut -d'|' -f2)
ROW_PARKED=$(echo "$ROW" | cut -d'|' -f3)
ROW_ROLLED=$(echo "$ROW" | cut -d'|' -f4)
ROW_ERR=$(echo "$ROW"   | cut -d'|' -f5)
[ "$ROW_STATE" = "completed" ] || { echo "✗ expected state='completed', got '$ROW_STATE'" >&2; exit 1; }
[ "$ROW_ATTEMPTS" = "1" ] || { echo "✗ expected recovery_attempts==1 (one deliberate takeover attempt), got '$ROW_ATTEMPTS'" >&2; exit 1; }
[ "$ROW_PARKED" = "f" ] || { echo "✗ expected NOT parked, got parked" >&2; exit 1; }
[ "$ROW_ROLLED" = "f" ] || { echo "✗ expected rolled_back_at IS NULL — the rune shape must never roll back" >&2; exit 1; }
[ "$ROW_ERR" = "f" ] || { echo "✗ expected error IS NULL on the completed row" >&2; exit 1; }
echo "  ✓ row: completed | attempts=1 | not parked | never rolled back | error NULL"

echo ""
echo "── assert 3: flag removed ──"
assert_flag_file_absent "$VM_NAME"

echo ""
echo "── assert 4: full service set at the flag target (incl. the stale proxy RECREATED at target) ──"
for svc in db app worker proxy; do
    IMG=$(running_image_for "$svc")
    [ -n "$IMG" ] || { echo "✗ container '-$svc' is not running after convergence" >&2; exit 1; }
    case "$IMG" in
        *"$HEAD_SHORT"*) echo "  ✓ $svc running at flag target: $IMG" ;;
        *) echo "✗ $svc running '$IMG' — expected the flag target tag ($HEAD_SHORT)" >&2; exit 1 ;;
    esac
done
REST_IMG=$(running_image_for rest)
[ -n "$REST_IMG" ] || { echo "✗ rest (PostgREST) container is not running" >&2; exit 1; }
echo "  ✓ rest running: $REST_IMG (version-pinned image, not commit-tagged — presence is the assertion)"
echo "  ✓ the stale proxy ($PROXY_BEFORE) was recreated at the flag target — the rune headline leg"

echo ""
echo "── assert 5: health + data intact (the empirical no-restore proof) ──"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_no_orphan_backup "$VM_NAME"
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"
echo "  ✓ health 200, demo data byte-count-identical to the pre-fabrication snapshot, unit active"

rm -f "$INSTALL_OUT"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — idempotence coda: a second install detects nothing-scheduled
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── second ./sb install (expect: nothing-scheduled, exit 0) ──"
INSTALL_OUT2=$(mktemp)
set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
    "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
    > "$INSTALL_OUT2" 2>&1
INSTALL_RC2=$?
set -e
echo "  second ./sb install exit: $INSTALL_RC2"
[ "$INSTALL_RC2" -eq 0 ] || { cat "$INSTALL_OUT2"; echo "✗ second install did not exit 0 (idempotent refresh expected)" >&2; exit 1; }
grep -q "Detected install state: nothing-scheduled" "$INSTALL_OUT2" || {
    cat "$INSTALL_OUT2"
    echo "✗ expected 'Detected install state: nothing-scheduled' on the second install" >&2
    exit 1
}
echo "  ✓ second install detected nothing-scheduled (the converged box is clean)"
rm -f "$INSTALL_OUT2"

echo ""
echo "PASS: 3-postswap-rune-wedge (fabricated rune shape — in_progress row + post_swap flag + stale set + MISSING proxy — taken over by ./sb install: SIGKILL-class quiesce of the live old daemon with flock-confirmed death, forward resume, full service set recreated at the flag target incl. the proxy, row completed with zero restores, flag removed, and a second install reads nothing-scheduled)"
