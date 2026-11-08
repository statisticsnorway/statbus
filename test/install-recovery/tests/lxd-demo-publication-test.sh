#!/usr/bin/env bash
# SYNTHETIC STATBUS-595 regression: real builder, reader, fork and reclaim,
# simulated LXD only. A synchronous reader runs before snapshot returns,
# making the publication interleaving deterministic without timing/retries.
# The backend is selected at runtime and provides reclaim plus VM globals.
# shellcheck disable=SC1090,SC1091,SC2034,SC2154
set -euo pipefail
ROOT=${STATBUS_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}
BACKEND=${STATBUS_TEST_BACKEND:-$ROOT/test/install-recovery/lib/lxd-backend.sh}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/demo-publication.XXXXXX")
fail() { echo "FAIL: $*" >&2; exit 1; }
export LXD_LOG_DIR=$TMP GITHUB_RUN_ID=595 LXD_MARKER_ID=builder-595
source "$BACKEND"
source "$ROOT/test/install-recovery/tests/fake-lxc.sh"
mk_fake_env "$TMP/env"
export FLEET_ACTIVE_DIR=$TMP/env/root/fleet-active
S=$FAKE_STORE
mkdir -p "$TMP/snapshots"
tag=v2099.01.1-rc.1
parent=installed-v2099.01.0-standalone
parent_base=$(_lxd_name "$tag-$parent")
base=$(_lxd_checkpoint_base "$tag" "$parent-demo")
mkdir -p "$S/$parent_base"
touch "$S/$parent_base/snap" "$FLEET_ACTIVE_DIR/$LXD_MARKER_ID"
# Deliberately inherited provenance differs from this demo producer.
printf old > "$S/$parent_base/user.statbus.producer"
printf old-run > "$S/$parent_base/user.statbus.run_id"
_lxd_ready() { VM_IP=10.0.0.2; }
lxd_capture_failure() { :; }
VM_EXEC() {
    case "$*" in
        *import-demo-data.sh*) echo load >> "$TMP/loads" ;;
        *'SELECT count('*|*'SELECT '\''statistical_unit='*) echo 0 ;;
        *) fail "unexpected guest command: $*" ;;
    esac
}
sleep() { printf '%s\n' "$1" >> "$TMP/sleeps"; }
_lxd_host() {
    case "$1" in
        flock) "$@" ;;
        lxc) case "$2" in
            snapshot)
                [ "${FAIL_AT:-}" != snapshot ] || return 73
                # Snapshot config is immutable in this model. Copying it must
                # use this frozen config, not the base's later mutable config.
                rm -rf "${TMP:?}/snapshots/$3"
                mkdir -p "$TMP/snapshots/$3"
                cp -R "$S/$3/." "$TMP/snapshots/$3/"
                lxc snapshot "$3" "$4"
                if [ "${OBSERVE:-0}" = 1 ]; then
                    local rc=0
                    ( OBSERVE=0 lxd_demo_ensure "$tag" "$parent" ) > "$TMP/reader.log" 2>&1 || rc=$?
                    printf '%s\n' "$rc" > "$TMP/reader.rc"
                fi
                ;;
            config)
                if [ "$3" = set ] && [ "${FAIL_AT:-}" = "$5" ]; then return 73; fi
                "$@" ;;
            copy)
                "$@" || return
                if [ -d "$TMP/snapshots/${3%/checkpoint}" ]; then
                    cp -R "$TMP/snapshots/${3%/checkpoint}/." "$S/$4/"
                    rm -f "$S/$4/snap"
                fi
                ;;
            info|delete|start|stop|exec) "$@" ;;
            *) fail "unexpected LXD command: $*" ;;
        esac ;;
        *) fail "unexpected transport: $*" ;;
    esac
}
assert_identity() {
    local dir=$1 key expected
    for key in demo_parent candidate producer run_id; do
        case "$key" in demo_parent) expected=$parent_base ;; candidate) expected=$tag ;; producer) expected=demo ;; run_id) expected=595 ;; esac
        [ "$(cat "$dir/user.statbus.$key" 2>/dev/null)" = "$expected" ] || fail "$dir $key must equal $expected"
    done
}
OBSERVE=1 lxd_demo_ensure "$tag" "$parent"
cat "$TMP/reader.log"
[ "$(cat "$TMP/reader.rc")" = 0 ] || fail 'reader at snapshot publication must reuse complete matching checkpoint'
assert_identity "$S/$base"
assert_identity "$TMP/snapshots/$base"
echo 'PASS: publication-boundary reader reuses complete identity on base and immutable snapshot'
lxd_demo_ensure "$tag" "$parent"
[ "$(wc -l < "$TMP/loads" | tr -d ' ')" = 1 ] || fail 'matching reuse must load once'
# Selector seam only: exercise real lxd_fork provenance gate and mechanical fork.
lxd_checkpoint_for_scenario() { printf '%s\n' "$parent-demo"; }
lxd_fork "$tag" fork-595
fork="$LXD_FORK_PREFIX-${tag//[^a-zA-Z0-9-]/-}-fork-595"
assert_identity "$S/$fork"
[ "$HARNESS_DEMO_PRELOADED" = 1 ] || fail 'demo consumer must receive preloaded flag'
printf wrong-candidate > "$S/$base/user.statbus.candidate"
rc=0; lxd_fork "$tag" refused-595 > "$TMP/candidate-mismatch.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "genuine candidate mismatch must refuse, got $rc"
printf '%s' "$tag" > "$S/$base/user.statbus.candidate"
assert_identity "$S/$fork"
echo 'PASS: matching reuse loads once, actual fork inherits snapshot identity, candidate mismatch refuses'
rm "$FLEET_ACTIVE_DIR/$LXD_MARKER_ID"
[ "$(bash -c "$_lxd_arc_a_reclaim_script" _ "$base" 3600)" = keep-ready ] || fail 'published checkpoint must survive builder disappearance'
lxd_demo_ensure "$tag" "$parent"
touch "$FLEET_ACTIVE_DIR/$LXD_MARKER_ID"
echo 'PASS: publication committed before builder exit remains reusable and protected from reclaim'
printf wrong-parent > "$S/$base/user.statbus.demo_parent"
rc=0; lxd_demo_ensure "$tag" "$parent" > "$TMP/mismatch.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "genuine mismatch must refuse, got $rc"
[ "$(wc -l < "$TMP/loads" | tr -d ' ')" = 1 ] || fail 'mismatch must preserve existing producer'
echo 'PASS: genuinely mismatched ready lineage is rejected'
# Simulated process interruption: fail each write or snapshot in the actual
# build function directly, leaving its claimed base as a killed caller would.
for boundary in user.statbus.demo_parent user.statbus.candidate user.statbus.producer user.statbus.run_id snapshot; do
    lxc delete "$base" --force
    lxc copy "$parent_base/checkpoint" "$base" -c "user.statbus.builder=$LXD_MARKER_ID"
    rc=0; FAIL_AT=$boundary _lxd_demo_build "$tag" "$base" "$parent_base" > "$TMP/crash-$boundary.log" 2>&1 || rc=$?
    [ "$rc" = 73 ] || fail "injected $boundary must stop builder, got $rc"
    : > "$TMP/sleeps"
    rc=0; DEMO_BUILD_WAIT_S=30 lxd_demo_ensure "$tag" "$parent" > "$TMP/live-$boundary.log" 2>&1 || rc=$?
    [ "$rc" = 1 ] || fail 'live incomplete builder must exhaust bounded wait'
    [ "$(cat "$TMP/sleeps")" = "$(printf '15\n15')" ] || fail 'reader must honor 30-second wait budget'
    [ "$(bash -c "$_lxd_arc_a_reclaim_script" _ "$base" 3600)" = keep-builder-alive ] || fail 'live incomplete builder must retain ownership'
    rm "$FLEET_ACTIVE_DIR/$LXD_MARKER_ID"
    [ "$(bash -c "$_lxd_arc_a_reclaim_script" _ "$base" 3600)" = "deleted builder-gone $LXD_MARKER_ID" ] || fail 'dead incomplete builder must be reclaimable'
    touch "$FLEET_ACTIVE_DIR/$LXD_MARKER_ID"
    lxd_demo_ensure "$tag" "$parent" > "$TMP/rebuild-$boundary.log" 2>&1
    assert_identity "$TMP/snapshots/$base"
    echo "PASS: interruption at $boundary keeps live ownership bounded, reclaims dead builder, rebuilds complete snapshot"
done
# Legacy unowned partial bases retain the same age-based reclamation rule.
lxc delete "$base" --force
lxc copy "$parent_base/checkpoint" "$base"
printf '2026/09/30 10:00 UTC' > "$S/$base/created"
[ "$(FLEET_NOW=1790764200 bash -c "$_lxd_arc_a_reclaim_script" _ "$base" 3600)" = keep-no-builder-fresh ] || fail 'fresh legacy claim must wait'
[ "$(FLEET_NOW=1790773200 bash -c "$_lxd_arc_a_reclaim_script" _ "$base" 3600)" = deleted\ no-builder-stale ] || fail 'stale legacy claim must be reclaimed'
echo 'PASS: legacy partial builder retains age-bounded reclaim'
echo "Artifacts: $TMP"
