#!/usr/bin/env bash
# Offline contract (STATBUS-517): each gate test forks the snapshot it needs.
# SYNTHETIC: a fake LXD store (tests/fake-lxc.sh), not a real guest. Runs the
# REAL lxd_checkpoint_for_scenario, lxd_fork, lxd_base_for_candidate,
# lxd_demo_ensure, install_statbus_in_vm / install_statbus_at_sha and
# populate_with_demo_data. Proves:
#  - LXD_START=installed-candidate scenarios fork installed-<candidate>, and
#    their FIRST candidate install is the checkpoint's (HEAD verified); the
#    second install runs for real; a wrong-HEAD fork fails, never reinstalls.
#  - baseline scenarios that load demo data fork installed-<prev>-demo, built
#    once from installed-<prev> by one real populate, reused afterwards;
#    their own populate_with_demo_data confirms instead of loading.
#  - candidate arcs fork installed-<candidate>-demo the same way.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
REPO=$TMP/repo
mkdir -p "$REPO/test/install-recovery/lib" "$REPO/test/install-recovery/scenarios" "$REPO/tmp"
cp "$ROOT/test/install-recovery/lib/"{lxd-backend,release-baseline,data-helpers}.sh "$REPO/test/install-recovery/lib/"
S_DIR=$REPO/test/install-recovery/scenarios
printf '#!/bin/bash\n# LXD_START=installed-candidate\nINSTALL_VERSION="${INSTALL_VERSION:-}"\nbootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"\n' > "$S_DIR/5-install-first.sh"
printf '#!/bin/bash\nINSTALL_VERSION="${INSTALL_VERSION:-}"\nbootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"\n' > "$S_DIR/5-install-empty.sh"
printf '#!/bin/bash\nINSTALL_VERSION=$(select_release_baseline_from_repo "$REPO_ROOT")\npopulate_with_demo_data "$VM_NAME"\n' > "$S_DIR/1-data-fault.sh"
printf '#!/bin/bash\nINSTALL_VERSION=$(select_release_baseline_from_repo "$REPO_ROOT")\n' > "$S_DIR/1-plain-fault.sh"
git -C "$REPO" init -q; git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false add .
git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm base; git -C "$REPO" tag v2099.01.0
git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm cand --allow-empty; git -C "$REPO" tag v2099.01.1-rc.1
CAND=$(git -C "$REPO" rev-parse HEAD)
export LXD_CANDIDATE=v2099.01.1-rc.1 LXD_FORK_PREFIX=s2 LXD_LOG_DIR=$TMP
# shellcheck disable=SC1091
source "$REPO/test/install-recovery/lib/lxd-backend.sh"
# shellcheck disable=SC1091
source "$REPO/test/install-recovery/lib/data-helpers.sh"
# shellcheck disable=SC1091
source "$ROOT/test/install-recovery/tests/fake-lxc.sh"
mk_fake_env "$TMP/env"; S=$FAKE_STORE
export FLEET_ACTIVE_DIR=$TMP/env/root/fleet-active
_lxd_mark() { printf '%s\n' "$*" >> "$TMP/marks"; }
_lxd_host() { "$@"; }
_lxd_ready() { return 0; }
_lxd_fork_from_base() { _lxd_host lxc info "$1" | grep -q checkpoint || return 1; lxc copy "$1/checkpoint" "$2"; VM_NAME=$2; }
_lxd_stage_candidate_install() { :; }
_lxd_upload() { :; }; _lxd_push() { :; }
VM_ROOT_EXEC() { return 0; }
lxd_capture_failure() { :; }
sleep() { :; }
LOADS=$TMP/loads; INSTALLS=$TMP/installs; : > "$LOADS"; : > "$INSTALLS"
# The guest's own work: a demo load and the drained-worker probe.
VM_EXEC() {
    case "$*" in
        *import-demo-data.sh*) echo "$VM_NAME" >> "$LOADS"; touch "$S/$VM_NAME/demo"; return 0 ;;
        *"FROM public.import_job WHERE state"*|*"FROM worker.tasks"*) echo 0 ;;
        *"bash -lc"*"./sb install"*) echo "$VM_NAME" >> "$INSTALLS" ;;
        *) echo ok ;;
    esac
}
VM_SCRIPT_INLINE() { cat >/dev/null; echo "$VM_NAME" >> "$INSTALLS"; }
mk_base() { mkdir -p "$S/$1"; touch "$S/$1/snap"; printf '%s' "$2" > "$S/$1/HEAD"; printf '%s' "$LXD_CANDIDATE" > "$S/$1/user.statbus.candidate"; printf 26.04 > "$S/$1/image.version"; }
CAND_BASE=s2-base-v2099-01-1-rc-1-installed-v2099-01-1-rc-1-standalone
PREV_BASE=s2-base-v2099-01-1-rc-1-installed-v2099-01-0-standalone
mk_base "$CAND_BASE" "$CAND"; mk_base "$PREV_BASE" "$(git -C "$REPO" rev-parse v2099.01.0)"

# 1. Checkpoint selection from the scenario's own declarations.
[ "$(lxd_checkpoint_for_scenario 5-install-first 2>/dev/null)" = "installed-v2099.01.1-rc.1-standalone" ] || fail "install-first scenario did not select installed-<candidate>"
[ "$(lxd_checkpoint_for_scenario 5-install-empty 2>/dev/null)" = hardened-nothing-installed ] || fail "install-time scenario left the empty checkpoint"
[ "$(lxd_checkpoint_for_scenario 1-data-fault 2>/dev/null)" = "installed-v2099.01.0-standalone-demo" ] || fail "data-loading baseline scenario did not select the demo layer"
[ "$(lxd_checkpoint_for_scenario 1-plain-fault 2>/dev/null)" = "installed-v2099.01.0-standalone" ] || fail "plain baseline scenario changed checkpoint"
[ "$(LXD_BASELINE_CHECKPOINT_SUFFIX=-pre lxd_checkpoint_for_scenario 1-data-fault 2>/dev/null)" = "installed-v2099.01.0-standalone-pre" ] || fail "smoke's suffixed baseline must keep loading data itself"
echo 'PASS: scenarios select empty / installed-candidate / installed-prev / installed-prev-demo from their own declarations'

# 2. Install-first fork: the first candidate install is the checkpoint's; the
#    second runs for real.
lxd_fork "$LXD_CANDIDATE" 5-install-first 2>/dev/null
[ "$LXD_CANDIDATE_PREINSTALLED" = 1 ] || fail "installed-candidate fork did not mark the preinstall"
install_statbus_in_vm "$VM_NAME"
[ ! -s "$INSTALLS" ] || fail "first install reinstalled over the checkpoint"
grep -q "preinstalled from checkpoint" "$TMP/marks" || fail "consumed preinstall left no log line"
install_statbus_in_vm "$VM_NAME"
[ "$(wc -l < "$INSTALLS" | tr -d ' ')" = 1 ] || fail "second install did not run for real"
echo 'PASS: install-first scenario consumes the checkpoint once, then installs for real'

# 2b. The tagged-install entry point consumes it the same way.
: > "$INSTALLS"; lxc delete s2-v2099-01-1-rc-1-5-install-first
lxd_fork "$LXD_CANDIDATE" 5-install-first 2>/dev/null
install_statbus_at_sha "$VM_NAME" "$CAND" "$LXD_CANDIDATE"
[ ! -s "$INSTALLS" ] || fail "tagged first install reinstalled over the checkpoint"
echo 'PASS: tagged candidate install consumes the checkpoint once'

# 2c. A fork whose HEAD is not the candidate fails, never reinstalls.
: > "$INSTALLS"; lxc delete s2-v2099-01-1-rc-1-5-install-first
printf 'f%.0s' {1..40} > "$S/$CAND_BASE/HEAD"
lxd_fork "$LXD_CANDIDATE" 5-install-first 2>/dev/null
rc=0; install_statbus_in_vm "$VM_NAME" 2>/dev/null || rc=$?
[ "$rc" = 2 ] || fail "wrong-HEAD fork returned $rc, expected refusal 2"
[ ! -s "$INSTALLS" ] || fail "wrong-HEAD fork fell back to an install"
printf '%s' "$CAND" > "$S/$CAND_BASE/HEAD"
echo 'PASS: a wrong-HEAD installed fork is refused, never reinstalled'

# 3. Baseline demo layer: built once by one real load, reused, then confirmed.
export LXD_MARKER_ID=job1; touch "$FLEET_ACTIVE_DIR/job1"
lxd_base_for_candidate "$LXD_CANDIDATE" installed-v2099.01.0-standalone-demo 2>"$TMP/demo.err" || { cat "$TMP/demo.err" >&2; fail "demo layer build failed"; }
DEMO=s2-base-v2099-01-1-rc-1-installed-v2099-01-0-demo
[ -e "$S/$DEMO/snap" ] || fail "demo layer checkpoint missing"
[ "$(cat "$S/$DEMO/user.statbus.demo_parent")" = "$PREV_BASE" ] || fail "demo layer parent not recorded"
[ "$(cat "$LOADS")" = "$DEMO" ] || fail "demo layer not built by exactly one load on itself: $(cat "$LOADS")"
lxd_base_for_candidate "$LXD_CANDIDATE" installed-v2099.01.0-standalone-demo 2>"$TMP/demo.err" || { cat "$TMP/demo.err" >&2; fail "demo layer build failed"; }
[ "$(wc -l < "$LOADS" | tr -d ' ')" = 1 ] || fail "existing demo layer was rebuilt"
lxd_fork "$LXD_CANDIDATE" 1-data-fault 2>/dev/null
[ -e "$S/$VM_NAME/demo" ] || fail "data fault fork lacks the demo dataset"
populate_with_demo_data "$VM_NAME" >/dev/null
[ "$(wc -l < "$LOADS" | tr -d ' ')" = 1 ] || fail "data fault loaded the dataset again"
echo 'PASS: installed-prev-demo is built once, forked, and the scenario confirms the data instead of loading it'

# 3b. A demo layer from another parent is refused.
printf other > "$S/$DEMO/user.statbus.demo_parent"
rc=0; lxd_demo_ensure "$LXD_CANDIDATE" installed-v2099.01.0-standalone 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "demo layer with a foreign parent accepted"
echo 'PASS: a demo layer built from another parent is refused'

# 4. Candidate arcs fork installed-<candidate>-demo.
printf smoke > "$S/$CAND_BASE/user.statbus.producer"
export BASE_SHA=$CAND HARNESS_ROOT=$REPO
_lxd_arc_a_merge_token() { :; }
: > "$LOADS"
bootstrap_install_test_vm statbus-arc-one ""
[ -e "$S/s2-v2099-01-1-rc-1-arc-one/demo" ] || fail "arc A lacks the demo dataset"
populate_with_demo_data "$VM_NAME" >/dev/null
bootstrap_install_test_vm statbus-arc-two ""
populate_with_demo_data "$VM_NAME" >/dev/null
[ "$(cat "$LOADS")" = s2-base-v2099-01-1-rc-1-installed-v2099-01-1-rc-1-demo ] || fail "arcs did not share one demo load: $(cat "$LOADS")"
echo 'PASS: candidate arcs share one installed-candidate-demo layer'
