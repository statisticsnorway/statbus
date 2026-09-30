#!/usr/bin/env bash
# Offline contract (STATBUS-425 M4): arc A selection and preinstalled-skip.
# SYNTHETIC: a fake LXD store, not a real guest. Real-guest behaviour (shallow
# clone fetch of B/C, .env/cert/token on a forked smoke snapshot, supersession
# classification) is NOT proven here.
# Exact-SHA arc A checkpoints. Runs the REAL
# lxd_arc_a_ensure / bootstrap_install_test_vm arc branch / install_statbus_at_sha
# against a fake LXD store (directories under $TMP/lxd). Proves: A is installed
# ONCE per exact commit and later arcs fork it (no reinstall); a different
# commit (historical pin) gets its own checkpoint; identity is the full sha, a
# wrong-HEAD guest is refused; a dead builder's half-built base is discarded;
# fork never reuses another commit's checkpoint.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export LXD_CANDIDATE=v2026.09.3-rc.17 LXD_FORK_PREFIX=s2 HARNESS_ROOT=$ROOT LXD_LOG_DIR=$TMP
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
source "$ROOT/test/install-recovery/tests/fake-lxc.sh"
mk_fake_env "$TMP/env"; S=$FAKE_STORE
export FLEET_ACTIVE_DIR=$TMP/env/root/fleet-active
_lxd_mark() { :; }
_lxd_host() { "$@"; }
_lxd_guest_ip() { echo 10.0.0.9; }
_lxd_ready() { return 0; }
_lxd_prepare_fresh_answers() { return 0; }
sleep() { :; }
INSTALLS="$TMP/installs"; : > "$INSTALLS"
_real_install_at_sha=$(declare -f install_statbus_at_sha)
# Stand-in for the real per-commit install (network): records it and stamps HEAD.
_do_install() { echo "$2" >> "$INSTALLS"; printf '%s' "${FAKE_HEAD:-$2}" > "$S/$1/HEAD"; }
install_statbus_at_sha() {
    if [ "${LXD_ARC_A_PREINSTALLED:-}" = "$2" ] && [ -z "${3:-}" ]; then echo "SKIP $2" >> "$TMP/skips"; return 0; fi
    _do_install "$1" "$2"
}
mkdir -p "$S/s2-base-v2026-09-3-rc-17-hardened-nothing-installed"; touch "$S/s2-base-v2026-09-3-rc-17-hardened-nothing-installed/snap"
REPO=$TMP/repo; git init -q "$REPO"; git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m c
git -C "$REPO" tag v2026.09.3-rc.17; export HARNESS_ROOT=$REPO
A=$(git -C "$REPO" rev-parse HEAD); PIN=$(printf 'b%.0s' {1..40})
SMOKE=$S/s2-base-v2026-09-3-rc-17-installed-v2026-09-3-rc-17-standalone
mk_smoke() { mkdir -p "$SMOKE"; touch "$SMOKE/snap"; printf '%s' v2026.09.3-rc.17 > "$SMOKE/user.statbus.candidate"; printf smoke > "$SMOKE/user.statbus.producer"; printf '%s' "${1:-$A}" > "$SMOKE/HEAD"; echo "release_status=prerelease version=v2026.09.3-rc.17" > "$SMOKE/upgrade-row"; }
mk_smoke
export LXD_MARKER_ID=job1; touch "$FLEET_ACTIVE_DIR/job1"

# 1. candidate A: fork smoke's LITERAL installed checkpoint. No install, no
#    A-checkpoint built, smoke's release metadata untouched, arc install skipped.
export BASE_SHA=$A
bootstrap_install_test_vm statbus-arc-one ""
[ ! -s "$INSTALLS" ] || fail "candidate arc ran an A install: $(cat "$INSTALLS")"
[ -d "$S/s2-v2026-09-3-rc-17-arc-one" ] || fail "arc fork not created"
[ "$(cat "$S/s2-v2026-09-3-rc-17-arc-one/upgrade-row")" = "release_status=prerelease version=v2026.09.3-rc.17" ] || fail "forked A metadata differs from smoke's"
for d in "$S"/*arc-a-*; do [ ! -e "$d" ] || fail "an exact-SHA checkpoint was built for the candidate commit: $d"; done
install_statbus_at_sha statbus-arc-one "$A"
[ -f "$TMP/skips" ] || fail "arc's own install_statbus_at_sha did not skip"
bootstrap_install_test_vm statbus-arc-two ""
[ ! -s "$INSTALLS" ] || fail "second candidate arc installed A"
echo 'PASS: candidate A arcs fork smoke installed checkpoint, no per-arc install, metadata untouched'

# 2. missing / unproven / wrong-HEAD smoke checkpoint fails loud, never reinstalls
unset LXD_ARC_A_PREINSTALLED; rm -f "$TMP/skips"
mv "$SMOKE" "$SMOKE.off"
rc=0; bootstrap_install_test_vm statbus-arc-nosmoke "" 2>"$TMP/err" || rc=$?
[ "$rc" -ne 0 ] && grep -q "never reinstall" "$TMP/err" || fail "missing smoke checkpoint not refused loudly"
[ ! -s "$INSTALLS" ] || fail "missing smoke checkpoint fell back to an install"
mv "$SMOKE.off" "$SMOKE"
printf other > "$SMOKE/user.statbus.producer"
rc=0; bootstrap_install_test_vm statbus-arc-badprod "" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "non-smoke provenance accepted"
mk_smoke "$(printf 'f%.0s' {1..40})"
rc=0; bootstrap_install_test_vm statbus-arc-badhead "" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "smoke checkpoint whose HEAD != BASE_SHA accepted"
mk_smoke
rc=0; BASE_SHA=abc bootstrap_install_test_vm statbus-arc-short "" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "short sha accepted"
[ ! -s "$INSTALLS" ] || fail "a refusal fell back to an install"
echo 'PASS: missing/unproven/wrong-HEAD/short-sha refuse loudly and never reinstall'

# 3. historical pin (a commit that is NOT the candidate): its own exact-SHA checkpoint
export BASE_SHA=$PIN; unset LXD_ARC_A_PREINSTALLED
bootstrap_install_test_vm statbus-arc-pin ""
[ "$(wc -l < "$INSTALLS" | tr -d ' ')" = 1 ] && [ "$(tail -1 "$INSTALLS")" = "$PIN" ] || fail "pin did not get its own install"
[ -d "$S/s2-base-v2026-09-3-rc-17-arc-a-bbbbbbbbbbbb" ] || fail "pin checkpoint missing"
echo 'PASS: historical pin gets its own exact-SHA checkpoint'

# 4. wrong HEAD in the guest is refused, and no checkpoint is left behind
BASE_SHA=$(printf 'c%.0s' {1..40}); export BASE_SHA; FAKE_HEAD=$A
rc=0; bootstrap_install_test_vm statbus-arc-bad "" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "guest HEAD != requested sha was accepted"
[ ! -d "$S/s2-base-v2026-09-3-rc-17-arc-a-cccccccccccc" ] || fail "failed build left a base behind"
unset FAKE_HEAD
echo 'PASS: identity is the exact sha; wrong HEAD is refused and cleaned up'

# 5. dead builder: half-built base is discarded and rebuilt
D=$(printf 'd%.0s' {1..40}); export BASE_SHA=$D
mkdir -p "$S/s2-base-v2026-09-3-rc-17-arc-a-dddddddddddd"; printf ghost > "$S/s2-base-v2026-09-3-rc-17-arc-a-dddddddddddd/user.statbus.builder"
bootstrap_install_test_vm statbus-arc-dead ""
[ -e "$S/s2-base-v2026-09-3-rc-17-arc-a-dddddddddddd/snap" ] || fail "half-built base from a dead builder was not replaced"
echo 'PASS: a dead builder never wedges later arcs'

# 6. missing hardened base fails loud
rm -rf "$S/s2-base-v2026-09-3-rc-17-hardened-nothing-installed"; BASE_SHA=$(printf 'e%.0s' {1..40}); export BASE_SHA
rc=0; bootstrap_install_test_vm statbus-arc-nohard "" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "missing hardened base accepted"
echo 'PASS: missing smoke hardened base fails loud'

# ── R5: atomic builder claim, aged legacy recovery ──────────────────────────
NOW_FMT() { date -u +'%Y/%m/%d %H:%M UTC'; }
BASE_OF() { printf '%s/s2-base-v2026-09-3-rc-17-arc-a-%s' "$S" "${1:0:12}"; }
mk_hard() { mkdir -p "$S/s2-base-v2026-09-3-rc-17-hardened-nothing-installed"; touch "$S/s2-base-v2026-09-3-rc-17-hardened-nothing-installed/snap"; }
mk_hard; export LXD_MARKER_ID=job1
E=$(printf '1%.0s' {1..40}); export BASE_SHA=$E

# 7. the builder key exists the instant the base does (set BY the copy, not after)
: > "$INSTALLS"
bootstrap_install_test_vm statbus-arc-r5a ""
[ "$(cat "$(BASE_OF "$E")/user.statbus.builder")" = job1 ] || fail "builder key not recorded by the claim"
echo 'PASS: builder key is applied by the claiming copy itself'

# 8. copy cannot apply the config: nothing created, loud failure, no wedge
F=$(printf '2%.0s' {1..40}); export BASE_SHA=$F
rc=0; FAKE_COPY_CONFIG_FAIL=1 bootstrap_install_test_vm statbus-arc-r5b "" 2>"$TMP/err" || rc=$?
[ "$rc" -ne 0 ] && grep -q "could not claim" "$TMP/err" || fail "config-failing copy not refused loudly"
[ ! -d "$(BASE_OF "$F")" ] || fail "config-failing copy left a base behind"
echo 'PASS: a claim whose config cannot be applied creates nothing and fails loud'

# 9. legacy/dead-claim base with NO builder: FRESH one is waited on (not deleted)
G=$(printf '3%.0s' {1..40}); export BASE_SHA=$G
mkdir -p "$(BASE_OF "$G")"; NOW_FMT > "$(BASE_OF "$G")/created"
rc=0; ARC_A_BUILD_WAIT_S=30 ARC_A_LEGACY_STALE_S=3600 bootstrap_install_test_vm statbus-arc-r5c "" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "fresh no-builder base was treated as free"
[ -d "$(BASE_OF "$G")" ] || fail "fresh no-builder base was deleted before the age threshold"
echo 'PASS: a fresh no-builder base is left alone and waited on, then refused after the budget'

# 10. same base, now OLDER than the threshold: recovered and rebuilt
printf '2020/01/01 00:00 UTC' > "$(BASE_OF "$G")/created"
: > "$INSTALLS"
ARC_A_LEGACY_STALE_S=3600 bootstrap_install_test_vm statbus-arc-r5d ""
[ -e "$(BASE_OF "$G")/snap" ] && [ "$(tail -1 "$INSTALLS")" = "$G" ] || fail "aged no-builder base not recovered and rebuilt"
echo 'PASS: an aged no-builder base is recovered under the host lock and rebuilt'

# 11. builder key set and its marker ALIVE: never deleted, however old
H2=$(printf '4%.0s' {1..40}); export BASE_SHA=$H2
mkdir -p "$(BASE_OF "$H2")"; printf '2020/01/01 00:00 UTC' > "$(BASE_OF "$H2")/created"
printf livebuilder > "$(BASE_OF "$H2")/user.statbus.builder"; touch "$FLEET_ACTIVE_DIR/livebuilder"
rc=0; ARC_A_BUILD_WAIT_S=30 bootstrap_install_test_vm statbus-arc-r5e "" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] && [ -d "$(BASE_OF "$H2")" ] || fail "a live builder's base was deleted or accepted"
echo 'PASS: a base whose builder marker is alive is never reclaimed'
