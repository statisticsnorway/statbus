#!/bin/bash
# Scenario: 5-install-source-image-identity-proof
# HARNESS_SKIP_DEFAULT — explicit acceptance proof for STATBUS-436 AC#4/#5.
#
# Goal:
#   Reproduce demo's real missing-tag condition on v2026.09.2, observe the old
#   daemon repeatedly refuse v2026.09.3 with the exact false mixed-tag error,
#   then run the named fixed candidate's official installer against the SAME
#   container state. The candidate must capture authoritative .Config.Image +
#   immutable .Image identities, exercise the db/app/worker/proxy target canary,
#   complete, preserve data, and remain healthy across scheduler ticks.
#
# This is deliberately on-demand. It consumes two historical release artifacts,
# a named candidate, and a long bounded observation window. Run it explicitly:
#   INSTALL_TARGET_TAG=v2026.10.0-rc.07 \
#     ./dev.sh test-install-recovery 5-install-source-image-identity-proof
#
# CANDIDATE_PATH selects which official path carries the candidate onto the
# looping box:
#   scheduled (default) — register + daemon-down schedule + installer inline
#     dispatch. Exercises the fixed source-identity capture itself (AC#5): the
#     carrier must bind every serving service's exact pre-pull identity.
#   operator — exactly what `./cloud.sh install demo <tag>` runs (AC#4, the
#     owner's demo remedy): a version-pinned install.sh with the old daemon
#     still looping, then cloud.sh's own post-steps (config generate + app up,
#     ensure the upgrade unit is started). No register, no schedule, no stop.
#     This path never reaches executeUpgrade, so there is no capture carrier;
#     instead it proves the false loop ENDS: the falsely-refused v2026.09.3 row
#     is superseded and no refusal appears after the install.

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-source-image-identity-proof}"
HARNESS_DEPLOYMENT_MODE="${HARNESS_DEPLOYMENT_MODE:-private}"
HARNESS_UPGRADE_CHANNEL="${HARNESS_UPGRADE_CHANNEL:-prerelease}"
OLD_RELEASE="${OLD_RELEASE:-v2026.09.2}"
OLD_TARGET="${OLD_TARGET:-v2026.09.3}"
OLD_LOOP_BUDGET_S="${OLD_LOOP_BUDGET_S:-4500}"
CANDIDATE_BUDGET_S="${CANDIDATE_BUDGET_S:-1200}"
SUSTAINED_CHECKS="${SUSTAINED_CHECKS:-4}"
SUSTAINED_INTERVAL_S="${SUSTAINED_INTERVAL_S:-65}"
CANDIDATE_PATH="${CANDIDATE_PATH:-scheduled}"
case "$CANDIDATE_PATH" in
    scheduled|operator) ;;
    *) echo "ERROR: CANDIDATE_PATH must be 'scheduled' or 'operator', got '$CANDIDATE_PATH'" >&2; exit 1 ;;
esac

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"

TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$' || true)
if [ -z "${INSTALL_TARGET_TAG:-}" ]; then
    [ -n "$TARGET_TAGS" ] || {
        echo "ERROR: this proof requires a named RC tag at HEAD; set INSTALL_TARGET_TAG explicitly for local discovery" >&2
        exit 1
    }
    INSTALL_TARGET_TAG=$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)
fi
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null || {
    echo "ERROR: INSTALL_TARGET_TAG '$INSTALL_TARGET_TAG' is not a release-shaped tag" >&2
    exit 1
}
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
TARGET_SHORT=${TARGET_SHA:0:8}
HEAD_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)
[ "$TARGET_SHA" = "$HEAD_SHA" ] || {
    echo "ERROR: INSTALL_TARGET_TAG '$INSTALL_TARGET_TAG' must point at HEAD ($HEAD_SHA), got $TARGET_SHA" >&2
    exit 1
}
OLD_SHA=$(git -C "$REPO_ROOT" rev-parse "${OLD_RELEASE}^{commit}")
OLD_TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${OLD_TARGET}^{commit}")
OLD_SHORT=${OLD_SHA:0:8}

source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

query_upgrade() {
    local sql=$1
    VM_EXEC bash -c "cd ~/statbus && ./sb psql -X -v ON_ERROR_STOP=1 -t -A -c \"$sql\"" 2>/dev/null | tr -d '\r'
}

unit_restarts() {
    VM_EXEC systemctl --user show statbus-upgrade@statbus.service --property=NRestarts --value 2>/dev/null | tr -d ' \r\n'
}

# Literal-$ bodies MUST NOT go through VM_EXEC bash -c: vm-bootstrap.sh's own
# header documents the sudo -i re-quoting trap that silently expands a bare
# `$` to empty (the first run of this proof died exactly there — 'no such
# service: ' from an emptied $service). VM_SCRIPT_INLINE is the sanctioned
# carrier for such bodies.
capture_identity_table() {
    VM_SCRIPT_INLINE capture-identity-table <<'REMOTE'
cd ~/statbus || exit 1
for service in db app worker rest proxy; do
    container=$(docker compose ps -q "$service")
    [ -n "$container" ] || { echo "missing|$service"; exit 1; }
    docker inspect --format "$service|{{.Id}}|{{.Config.Image}}|{{.Image}}|{{.State.Status}}" "$container"
done
REMOTE
}

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 5-install-source-image-identity-proof (explicit only)"
echo "  Old daemon: $OLD_RELEASE ($OLD_SHA)"
echo "  False target: $OLD_TARGET ($OLD_TARGET_SHA)"
echo "  Fixed candidate: $INSTALL_TARGET_TAG ($TARGET_SHA)"
echo "  Candidate path: $CANDIDATE_PATH"
echo "════════════════════════════════════════════════════════════════"

bootstrap_install_test_vm "$VM_NAME" "$OLD_RELEASE"
install_statbus_in_vm "$VM_NAME" "$OLD_RELEASE"
assert_health_passes "$VM_NAME"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")

CHECKOUT_BEFORE=$(VM_EXEC git -C /home/statbus/statbus rev-parse HEAD | tr -d ' \r\n')
[ "$CHECKOUT_BEFORE" = "$OLD_SHA" ] || { echo "old checkout mismatch: $CHECKOUT_BEFORE" >&2; exit 1; }
BINARY_BEFORE=$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version' | tr -d '\r')
SERVICE_PID=$(VM_EXEC systemctl --user show statbus-upgrade@statbus.service --property=MainPID --value | tr -d ' \r\n')
RESIDENT_BEFORE=$(VM_EXEC readlink -f "/proc/$SERVICE_PID/exe" | tr -d '\r')
RESTARTS_BEFORE=$(unit_restarts)
echo "  checkout before: $CHECKOUT_BEFORE"
echo "  binary before: $BINARY_BEFORE"
echo "  resident executable: $RESIDENT_BEFORE (pid $SERVICE_PID)"
echo "  NRestarts before: $RESTARTS_BEFORE"

echo "── authoritative source identities before tag removal ──"
IDENTITIES_BEFORE=$(capture_identity_table)
printf '%s\n' "$IDENTITIES_BEFORE"
for service in app worker proxy; do
    line=$(printf '%s\n' "$IDENTITIES_BEFORE" | grep "^$service|")
    config_image=$(printf '%s\n' "$line" | cut -d'|' -f3)
    case "$config_image" in
        *":$OLD_SHORT") ;;
        *) echo "$service .Config.Image does not name source commit $OLD_SHORT: $config_image" >&2; exit 1 ;;
    esac
done

echo "── removing source tags while preserving image content under neutral aliases ──"
VM_SCRIPT_INLINE remove-source-tags <<'REMOTE'
cd ~/statbus || exit 1
for service in app worker proxy; do
    container=$(docker compose ps -q "$service")
    config_image=$(docker inspect --format "{{.Config.Image}}" "$container")
    image_id=$(docker inspect --format "{{.Image}}" "$container")
    docker tag "$image_id" "statbus-proof-preserve/$service:source"
    docker image rm "$config_image"
done
REMOTE

IDENTITIES_MISSING_TAG=$(capture_identity_table)
printf '%s\n' "$IDENTITIES_MISSING_TAG"
[ "$IDENTITIES_MISSING_TAG" = "$IDENTITIES_BEFORE" ] || {
    echo "container identities changed while removing tag metadata" >&2
    diff <(printf '%s\n' "$IDENTITIES_BEFORE") <(printf '%s\n' "$IDENTITIES_MISSING_TAG") >&2 || true
    exit 1
}
COMPOSE_DISPLAY=$(VM_EXEC bash -c 'cd ~/statbus && docker compose ps --all --format "{{.Service}}|{{.Image}}"' | tr -d '\r')
printf '%s\n' "$COMPOSE_DISPLAY"
for service in app worker proxy; do
    display=$(printf '%s\n' "$COMPOSE_DISPLAY" | grep "^$service|" | cut -d'|' -f2-)
    case "$display" in
        sha256:*) ;;
        *) echo "$service Compose display did not fall back to sha256 after tag loss: $display" >&2; exit 1 ;;
    esac
done

# Capture only logs created by this proof.
OLD_LOG_SINCE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register '$OLD_TARGET'"
wait_for_upgrade_candidate_ready "$VM_NAME" "$OLD_TARGET_SHA" 900
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule '$OLD_TARGET'"

echo "── bounded observation of the released false-refusal loop ──"
# The claim is NOT quick on v2026.09.2 (traced, per the plan's open
# hypothesis): the old daemon's discovery verifyArtifacts backlog runs ON THE
# MAIN GOROUTINE (~12s per candidate over hundreds of freshly discovered rows),
# and every claim path — boot, 30s heartbeat, NOTIFY — waits behind it. The
# first live run of this proof expired at 180s with refusals=0 while the
# journal showed nothing but one-verify-per-12s the whole window. The watch
# therefore spans the backlog: each 'Images verified' line IS the daemon's own
# designed progress (STATBUS-195 watchdog-feeding), so a stall means no new
# journal line at all, not merely no refusal yet.
START=$(date +%s)
REFUSALS=0
ATTEMPTS=0
LAST_LOG_LINES=0
STALL_S=0
while true; do
    elapsed=$(( $(date +%s) - START ))
    LOG=$(VM_EXEC journalctl --user -u statbus-upgrade@statbus.service --since "$OLD_LOG_SINCE" --no-pager 2>/dev/null || true)
    REFUSALS=$(printf '%s\n' "$LOG" | grep -c 'Could not record immutable source image identities before target pull:' || true)
    ATTEMPTS=$(query_upgrade "SELECT CASE WHEN started_at IS NULL THEN 0 ELSE 1 END FROM public.upgrade WHERE commit_sha = '$OLD_TARGET_SHA' ORDER BY id DESC LIMIT 1;" | tr -d ' ')
    ATTEMPTS=${ATTEMPTS:-0}
    if [ "$REFUSALS" -ge 2 ] && [ "$ATTEMPTS" -eq 1 ]; then
        break
    fi
    LOG_LINES=$(printf '%s\n' "$LOG" | grep -c . || true)
    if [ "$LOG_LINES" -gt "$LAST_LOG_LINES" ]; then
        LAST_LOG_LINES=$LOG_LINES
        STALL_S=0
    else
        STALL_S=$((STALL_S + 10))
        [ "$STALL_S" -lt 300 ] || {
            printf '%s\n' "$LOG" >&2
            echo "old daemon journal silent for ${STALL_S}s without a refusal — wedged, not backlog-slow (refusals=$REFUSALS attempt_started=$ATTEMPTS)" >&2
            exit 1
        }
    fi
    [ "$elapsed" -lt "$OLD_LOOP_BUDGET_S" ] || {
        printf '%s\n' "$LOG" >&2
        echo "old daemon did not expose two false refusals within ${OLD_LOOP_BUDGET_S}s (refusals=$REFUSALS attempt_started=$ATTEMPTS)" >&2
        exit 1
    }
    sleep 10
done
printf '%s\n' "$LOG" | grep -F 'source serving era cannot be established: pre-upgrade source containers have mixed tags:' >/dev/null
# The "want common source tag" value is NOT the source commit tag: the old
# daemon compares Compose DISPLAY strings, so each sha256 display fallback
# extracts as a distinct hex "tag" (extractImageTag takes everything after
# the last colon — the bare digest, no sha256: prefix). The wanted "common
# tag" is therefore the FIRST service's own display digest, and demanding a
# digest as the common tag IS the false refusal: .Config.Image held one
# coherent source the whole time (this proof already asserted
# IDENTITIES_MISSING_TAG == IDENTITIES_BEFORE). The second live run died
# here on the guessed '"$OLD_SHORT"' shape; the real message shape is
# '<svc> uses "<hex>", want common source tag "<hex>"'.
printf '%s\n' "$LOG" | grep -E 'uses "[0-9a-f]{12,64}", want common source tag "[0-9a-f]{12,64}"' >/dev/null
RESTARTS_DURING_LOOP=$(unit_restarts)
[ "$RESTARTS_DURING_LOOP" = "$RESTARTS_BEFORE" ] || {
    echo "old loop restarted the systemd unit: before=$RESTARTS_BEFORE during=$RESTARTS_DURING_LOOP" >&2
    exit 1
}
echo "  ✓ observed $REFUSALS exact source-capture refusals in one resident daemon"
query_upgrade "SELECT id, commit_version, commit_sha, state, started_at, error, recovery_parked_at FROM public.upgrade WHERE commit_sha = '$OLD_TARGET_SHA' ORDER BY id DESC LIMIT 1;"

CANDIDATE_INSTALL_SCRIPT=$(mktemp)
cp "$REPO_ROOT/install.sh" "$CANDIDATE_INSTALL_SCRIPT"
upload_install_script_to_vm "$VM_NAME" "$CANDIDATE_INSTALL_SCRIPT" /tmp/statbus-install.sh
INSTALL_LOG=$(mktemp)

# The official version-pinned installer, with the installer's own documented
# retry for the upgrade-in-progress class (an operator who meets that message
# waits and re-runs). Every refused attempt's full output is preserved.
run_official_installer() {
    local attempt=0 rc started
    started=$(date +%s)
    while true; do
        attempt=$((attempt + 1))
        rc=0
        VM_EXEC bash -c "cd ~ && STATBUS_INSTALL_VERSION='$INSTALL_TARGET_TAG' bash /tmp/statbus-install.sh --non-interactive" >"$INSTALL_LOG" 2>&1 || rc=$?
        [ "$rc" -eq 0 ] && break
        if grep -qF 'An upgrade is already running' "$INSTALL_LOG" && [ $(( $(date +%s) - started )) -lt 1800 ]; then
            echo "  … an upgrade hold blocks the installer — attempt $attempt refused (exit $rc); retrying the official installer in 30s"
            echo "  ── attempt $attempt full output ──"
            sed 's/^/  │ /' "$INSTALL_LOG"
            echo "  ── end attempt $attempt (exit $rc) ──"
            sleep 30
            continue
        fi
        cat "$INSTALL_LOG" >&2
        exit 1
    done
    cat "$INSTALL_LOG"
}

if [ "$CANDIDATE_PATH" = scheduled ]; then
# Preserve the candidate's pre-pull identity carrier before terminal cleanup.
VM_SCRIPT_INLINE arm-carrier-watch <<'REMOTE'
rm -f ~/statbus/tmp/statbus-436-captured-source-images.json
nohup bash -c 'for i in $(seq 1 24000); do if [ -s "$HOME/statbus/tmp/upgrade-source-images.json" ]; then cp "$HOME/statbus/tmp/upgrade-source-images.json" "$HOME/statbus/tmp/statbus-436-captured-source-images.json"; exit 0; fi; sleep 0.05; done; exit 1' >~/statbus/tmp/statbus-436-carrier-watch.log 2>&1 &
REMOTE
harness_register_log statbus-436-carrier-watch /home/statbus/statbus/tmp/statbus-436-carrier-watch.log

# The capture under test lives in executeUpgrade's pipeline (source capture
# before the target pull), reached by the daemon OR by ./sb install's inline
# dispatch of a 'scheduled' row — NOT by a plain version install (the sixth
# live run proved it: the installer completed and no carrier existed). The
# official choreography that exercises it THROUGH the missing-tag condition is
# the arc-proven daemon-down pattern: register + wait ready with the old
# daemon UP (its verify flips docker_images_status in seconds), stop the old
# daemon so it cannot claim the row, schedule, then let the official installer
# swap the binary and inline-dispatch the row through the NEW code while the
# source containers still display sha256.
echo "── register $INSTALL_TARGET_TAG (old daemon up, then down for the schedule) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register '$INSTALL_TARGET_TAG'"
wait_for_upgrade_candidate_ready "$VM_NAME" "$TARGET_SHA" 900
VM_EXEC systemctl --user stop statbus-upgrade@statbus.service
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule '$INSTALL_TARGET_TAG'"

echo "── official candidate installer: inline dispatch of the scheduled row through the missing-tag condition ──"
# With the old daemon down there is no loop to collide with; the retry belt
# stays for the same operator-surface reason (a transient refusal of the
# upgrade-in-progress class gets the installer's own documented retry, with
# every attempt's full output preserved).
run_official_installer

# The daemon-down schedule (required so the OLD daemon could not claim the
# target row and run its own broken capture) leaves the unit INACTIVE, and
# the inline dispatch deliberately does not start an inactive unit
# (restartUpgradeService's is-active gate; the inline handoff leaves service
# orchestration to the caller). The official reactivation is the installer's
# own lifecycle: a plain ./sb install re-run is idempotent, detects
# nothing-scheduled, refreshes the step table, and queues the daemon start
# at install exit (STATBUS-432's final-act dispatch). No manual systemctl
# restart — the operator's own command, exactly as on a real box.
echo "── official daemon reactivation (idempotent ./sb install re-run) ──"
VM_EXEC bash -c "cd ~/statbus && ./sb install --non-interactive"
assert_systemd_active "$VM_NAME"
else
# Operator remedy: cloud.sh's cmd_install_one with a pinned version, verbatim
# in substance — the pinned install.sh over SSH while the old daemon keeps
# looping (no stop: cloud.sh forbids the SIGTERM pre-stop), then its two
# post-steps. The install's own final act restarts the drifted unit onto the
# candidate binary; cloud.sh's ensure_service_started is a no-op start then.
echo "── operator remedy: version-pinned official installer with the false loop still running (./cloud.sh install <box> $INSTALL_TARGET_TAG) ──"
run_official_installer
INSTALL_END_SINCE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
echo "── cloud.sh post-steps: config generate + app up, ensure the upgrade unit is started ──"
VM_EXEC bash -c "cd ~/statbus && ./sb config generate && docker compose up -d app"
VM_EXEC systemctl --user start statbus-upgrade@statbus.service
assert_systemd_active "$VM_NAME"
fi

START=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - START ))
    FINAL_STATE=$(query_upgrade "SELECT state FROM public.upgrade WHERE commit_sha = '$TARGET_SHA' ORDER BY id DESC LIMIT 1;" | tr -d ' ')
    case "$FINAL_STATE" in
        completed) break ;;
        superseded)
            # NOT a proof failure: the OLD daemon's verifyArtifacts auto-supersede
            # (v2026.09.2's "intermediate commit rows that are ancestors of a
            # verified commit") marked the target's pre-existing commit row when
            # a NEWER master commit's images verified — ledger bookkeeping, fired
            # before the candidate install ever ran. The install itself completed
            # ('Installation complete!'), and the at-target assertions below
            # (HEAD == TARGET_SHA, resident binary, serving health) are the
            # completion evidence — the fifth live run died here on exactly this
            # misread. A failure row remains terminal.
            echo "  (target row is superseded by ledger bookkeeping — the box itself installed and serves the target; continuing)"
            break ;;
        failed|rolled_back|dismissed)
            query_upgrade "SELECT id, state, error, recovery_parked_at, recovery_parked_reason FROM public.upgrade WHERE commit_sha = '$TARGET_SHA' ORDER BY id DESC LIMIT 1;" >&2
            exit 1
            ;;
    esac
    [ "$elapsed" -lt "$CANDIDATE_BUDGET_S" ] || { echo "candidate did not complete within ${CANDIDATE_BUDGET_S}s (state=$FINAL_STATE)" >&2; exit 1; }
    sleep 5
done

if [ "$CANDIDATE_PATH" = scheduled ]; then
CARRIER=$(VM_EXEC cat /home/statbus/statbus/tmp/statbus-436-captured-source-images.json 2>/dev/null || true)
[ -n "$CARRIER" ] || { echo "candidate source-image carrier was not captured" >&2; exit 1; }
printf '%s\n' "$CARRIER"
printf '%s\n' "$CARRIER" | grep -F "\"commit_sha\": \"$TARGET_SHA\"" >/dev/null
# Every serving service's carrier entry must bind the EXACT pre-pull identity
# (reference + immutable ID) recorded in IDENTITIES_BEFORE — rest included.
# Parse the JSON per service inside the guest (jq-on-guest is an accepted
# harness assumption, cf. 3-postswap-resume-died-parked.sh): a missing key
# yields '|' and mismatches, an exact match proves the canary/source carrier
# side of AC#5 for all four services, not just three.
for service in app worker rest proxy; do
    old_ref=$(printf '%s\n' "$IDENTITIES_BEFORE" | grep "^$service|" | cut -d'|' -f3)
    old_id=$(printf '%s\n' "$IDENTITIES_BEFORE" | grep "^$service|" | cut -d'|' -f4)
    got=$(VM_EXEC bash -c "jq -r '.source_serving_images[\"$service\"].reference + \"|\" + .source_serving_images[\"$service\"].image_id' ~/statbus/tmp/statbus-436-captured-source-images.json" | tr -d '\r')
    [ "$got" = "$old_ref|$old_id" ] || { echo "carrier $service identity mismatch: got '$got' want '$old_ref|$old_id'" >&2; exit 1; }
done
echo "  ✓ carrier binds exact reference + immutable ID for app, worker, rest, proxy"
fi

echo "── terminal identity, canary, data, and sustained-availability checks ──"
[ "$(VM_EXEC git -C /home/statbus/statbus rev-parse HEAD | tr -d ' \r\n')" = "$TARGET_SHA" ]
FINAL_PID=$(VM_EXEC systemctl --user show statbus-upgrade@statbus.service --property=MainPID --value | tr -d ' \r\n')
[ -n "$FINAL_PID" ] && [ "$FINAL_PID" != 0 ] || { echo "no resident upgrade daemon after the official reactivation (MainPID=$FINAL_PID)" >&2; exit 1; }
FINAL_RESIDENT=$(VM_EXEC readlink -f "/proc/$FINAL_PID/exe" | tr -d '\r')
FINAL_BINARY=$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version' | tr -d '\r')
echo "  final binary: $FINAL_BINARY"
echo "  final resident executable: $FINAL_RESIDENT (pid $FINAL_PID)"
# The fixed candidate must be the RESIDENT program, not merely the checkout:
# the on-disk binary names the candidate commit, and the daemon's own
# executable is that same binary.
case "$FINAL_BINARY" in
    *"$TARGET_SHORT"*) ;;
    *) echo "on-disk binary is not the candidate: $FINAL_BINARY (want commit $TARGET_SHORT)" >&2; exit 1 ;;
esac
case "$FINAL_RESIDENT" in
    */statbus/sb) ;;
    *) echo "resident daemon executable is not the checkout's sb: $FINAL_RESIDENT" >&2; exit 1 ;;
esac
echo "  ✓ resident program is the fixed candidate ($FINAL_BINARY at $FINAL_RESIDENT)"
query_upgrade "SELECT id, commit_version, commit_sha, state, error FROM public.upgrade WHERE commit_sha = '$TARGET_SHA' ORDER BY id DESC LIMIT 1;"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_active "$VM_NAME"

FINAL_IDENTITIES=$(capture_identity_table)
printf '%s\n' "$FINAL_IDENTITIES"
for service in db app worker proxy; do
    final_ref=$(printf '%s\n' "$FINAL_IDENTITIES" | grep "^$service|" | cut -d'|' -f3)
    case "$final_ref" in
        *":$TARGET_SHORT") ;;
        *) echo "corrected db/app/worker/proxy canary did not converge $service to $TARGET_SHORT: $final_ref" >&2; exit 1 ;;
    esac
done

RESTARTS_AFTER=$(unit_restarts)
for check in $(seq 1 "$SUSTAINED_CHECKS"); do
    assert_health_passes "$VM_NAME"
    assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
    state=$(query_upgrade "SELECT state FROM public.upgrade WHERE commit_sha = '$TARGET_SHA' ORDER BY id DESC LIMIT 1;" | tr -d ' ')
    # Same terminal contract as the completion watch above: 'completed' (the
    # inline dispatch's own row) or the ledger-bookkeeping 'superseded' (the
    # old daemon's ancestor auto-supersede, which predates the candidate run)
    # pass; failed/rolled_back/dismissed fail. Requiring exactly 'completed'
    # here would reintroduce the fifth run's misread one phase later.
    case "$state" in
        completed|superseded) ;;
        *) echo "candidate left a passing terminal state during sustained check $check: $state" >&2; exit 1 ;;
    esac
    current_restarts=$(unit_restarts)
    [ "$current_restarts" = "$RESTARTS_AFTER" ] || { echo "upgrade daemon restarted during sustained observation: $RESTARTS_AFTER -> $current_restarts" >&2; exit 1; }
    [ "$check" -eq "$SUSTAINED_CHECKS" ] || sleep "$SUSTAINED_INTERVAL_S"
done

if [ "$CANDIDATE_PATH" = operator ]; then
    # The loop is over only if the falsely-refused row can no longer be
    # rescheduled (terminal 'superseded', written by the install's post-
    # completion upgrade_supersede_older) and the resident candidate daemon
    # logged no refusal at all after the install, across every sustained tick.
    OLD_TARGET_STATE=$(query_upgrade "SELECT state FROM public.upgrade WHERE commit_sha = '$OLD_TARGET_SHA' ORDER BY id DESC LIMIT 1;" | tr -d ' ')
    query_upgrade "SELECT id, commit_version, state, superseded_at, error FROM public.upgrade WHERE commit_sha = '$OLD_TARGET_SHA' ORDER BY id DESC LIMIT 1;"
    [ "$OLD_TARGET_STATE" = superseded ] || { echo "the falsely-refused $OLD_TARGET row was not superseded by the remedy: state=$OLD_TARGET_STATE" >&2; exit 1; }
    POST_LOG=$(VM_EXEC journalctl --user -u statbus-upgrade@statbus.service --since "$INSTALL_END_SINCE" --no-pager 2>/dev/null || true)
    POST_REFUSALS=$(printf '%s\n' "$POST_LOG" | grep -c 'Could not record immutable source image identities before target pull:' || true)
    POST_ATTEMPTS=$(printf '%s\n' "$POST_LOG" | grep -c "Executing upgrade to $OLD_TARGET" || true)
    [ "$POST_REFUSALS" -eq 0 ] && [ "$POST_ATTEMPTS" -eq 0 ] || {
        printf '%s\n' "$POST_LOG" >&2
        echo "the false loop continued after the remedy: refusals=$POST_REFUSALS attempts=$POST_ATTEMPTS since $INSTALL_END_SINCE" >&2
        exit 1
    }
    echo "  ✓ false loop ended: $OLD_TARGET row superseded, zero refusals and zero re-attempts since the install"
    echo "PASS: old v2026.09.2 false loop reproduced; the operator remedy (pinned $INSTALL_TARGET_TAG install) completed and ended the loop"
else
    echo "PASS: old v2026.09.2 false loop reproduced; $INSTALL_TARGET_TAG captured daemon identities and completed through the official installer"
fi
