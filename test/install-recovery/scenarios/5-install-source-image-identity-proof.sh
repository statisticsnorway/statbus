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

set -euo pipefail

VM_NAME="${1:-statbus-recovery-5-install-source-image-identity-proof}"
HARNESS_DEPLOYMENT_MODE="${HARNESS_DEPLOYMENT_MODE:-private}"
HARNESS_UPGRADE_CHANNEL="${HARNESS_UPGRADE_CHANNEL:-prerelease}"
OLD_RELEASE="${OLD_RELEASE:-v2026.09.2}"
OLD_TARGET="${OLD_TARGET:-v2026.09.3}"
OLD_LOOP_BUDGET_S="${OLD_LOOP_BUDGET_S:-180}"
CANDIDATE_BUDGET_S="${CANDIDATE_BUDGET_S:-1200}"
SUSTAINED_CHECKS="${SUSTAINED_CHECKS:-4}"
SUSTAINED_INTERVAL_S="${SUSTAINED_INTERVAL_S:-65}"

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
START=$(date +%s)
REFUSALS=0
ATTEMPTS=0
while true; do
    elapsed=$(( $(date +%s) - START ))
    LOG=$(VM_EXEC journalctl --user -u statbus-upgrade@statbus.service --since "$OLD_LOG_SINCE" --no-pager 2>/dev/null || true)
    REFUSALS=$(printf '%s\n' "$LOG" | grep -c 'Could not record immutable source image identities before target pull:' || true)
    ATTEMPTS=$(query_upgrade "SELECT CASE WHEN started_at IS NULL THEN 0 ELSE 1 END FROM public.upgrade WHERE commit_sha = '$OLD_TARGET_SHA' ORDER BY id DESC LIMIT 1;" | tr -d ' ')
    ATTEMPTS=${ATTEMPTS:-0}
    if [ "$REFUSALS" -ge 2 ] && [ "$ATTEMPTS" -eq 1 ]; then
        break
    fi
    [ "$elapsed" -lt "$OLD_LOOP_BUDGET_S" ] || {
        printf '%s\n' "$LOG" >&2
        echo "old daemon did not expose two false refusals within ${OLD_LOOP_BUDGET_S}s (refusals=$REFUSALS attempt_started=$ATTEMPTS)" >&2
        exit 1
    }
    sleep 2
done
printf '%s\n' "$LOG" | grep -F 'source serving era cannot be established: pre-upgrade source containers have mixed tags:' >/dev/null
printf '%s\n' "$LOG" | grep -F "want common source tag \"$OLD_SHORT\"" >/dev/null
RESTARTS_DURING_LOOP=$(unit_restarts)
[ "$RESTARTS_DURING_LOOP" = "$RESTARTS_BEFORE" ] || {
    echo "old loop restarted the systemd unit: before=$RESTARTS_BEFORE during=$RESTARTS_DURING_LOOP" >&2
    exit 1
}
echo "  ✓ observed $REFUSALS exact source-capture refusals in one resident daemon"
query_upgrade "SELECT id, commit_version, commit_sha, state, started_at, error, recovery_parked_at FROM public.upgrade WHERE commit_sha = '$OLD_TARGET_SHA' ORDER BY id DESC LIMIT 1;"

# Preserve the candidate's pre-pull identity carrier before terminal cleanup.
VM_SCRIPT_INLINE arm-carrier-watch <<'REMOTE'
rm -f ~/statbus/tmp/statbus-436-captured-source-images.json
nohup bash -c 'for i in $(seq 1 24000); do if [ -s "$HOME/statbus/tmp/upgrade-source-images.json" ]; then cp "$HOME/statbus/tmp/upgrade-source-images.json" "$HOME/statbus/tmp/statbus-436-captured-source-images.json"; exit 0; fi; sleep 0.05; done; exit 1' >~/statbus/tmp/statbus-436-carrier-watch.log 2>&1 &
REMOTE
harness_register_log statbus-436-carrier-watch /home/statbus/statbus/tmp/statbus-436-carrier-watch.log

CANDIDATE_INSTALL_SCRIPT=$(mktemp)
cp "$REPO_ROOT/install.sh" "$CANDIDATE_INSTALL_SCRIPT"
upload_install_script_to_vm "$VM_NAME" "$CANDIDATE_INSTALL_SCRIPT" /tmp/statbus-install.sh
INSTALL_LOG=$(mktemp)
echo "── official candidate installer against the unchanged missing-tag condition ──"
if ! VM_EXEC bash -c "cd ~ && STATBUS_INSTALL_VERSION='$INSTALL_TARGET_TAG' bash /tmp/statbus-install.sh --non-interactive" >"$INSTALL_LOG" 2>&1; then
    cat "$INSTALL_LOG" >&2
    exit 1
fi
cat "$INSTALL_LOG"

START=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - START ))
    FINAL_STATE=$(query_upgrade "SELECT state FROM public.upgrade WHERE commit_sha = '$TARGET_SHA' ORDER BY id DESC LIMIT 1;" | tr -d ' ')
    case "$FINAL_STATE" in
        completed) break ;;
        failed|rolled_back|dismissed|superseded)
            query_upgrade "SELECT id, state, error, recovery_parked_at, recovery_parked_reason FROM public.upgrade WHERE commit_sha = '$TARGET_SHA' ORDER BY id DESC LIMIT 1;" >&2
            exit 1
            ;;
    esac
    [ "$elapsed" -lt "$CANDIDATE_BUDGET_S" ] || { echo "candidate did not complete within ${CANDIDATE_BUDGET_S}s (state=$FINAL_STATE)" >&2; exit 1; }
    sleep 5
done

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

echo "── terminal identity, canary, data, and sustained-availability checks ──"
[ "$(VM_EXEC git -C /home/statbus/statbus rev-parse HEAD | tr -d ' \r\n')" = "$TARGET_SHA" ]
FINAL_PID=$(VM_EXEC systemctl --user show statbus-upgrade@statbus.service --property=MainPID --value | tr -d ' \r\n')
FINAL_RESIDENT=$(VM_EXEC readlink -f "/proc/$FINAL_PID/exe" | tr -d '\r')
FINAL_BINARY=$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version' | tr -d '\r')
echo "  final binary: $FINAL_BINARY"
echo "  final resident executable: $FINAL_RESIDENT (pid $FINAL_PID)"
query_upgrade "SELECT id, commit_version, commit_sha, state, error FROM public.upgrade WHERE commit_sha = '$TARGET_SHA' ORDER BY id DESC LIMIT 1;"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_systemd_active "$VM_NAME"

TARGET_SHORT=${TARGET_SHA:0:8}
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
    [ "$state" = completed ] || { echo "candidate left completed state during sustained check $check: $state" >&2; exit 1; }
    current_restarts=$(unit_restarts)
    [ "$current_restarts" = "$RESTARTS_AFTER" ] || { echo "upgrade daemon restarted during sustained observation: $RESTARTS_AFTER -> $current_restarts" >&2; exit 1; }
    [ "$check" -eq "$SUSTAINED_CHECKS" ] || sleep "$SUSTAINED_INTERVAL_S"
done

echo "PASS: old v2026.09.2 false loop reproduced; $INSTALL_TARGET_TAG captured daemon identities and completed through the official installer"
