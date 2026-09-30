#!/usr/bin/env bash
# Offline contract for the shared arc verdict + slot wrapper (STATBUS-425 M4).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
source "$ROOT/ops/lxd-fleet/marker.sh"
source "$ROOT/test/install-recovery/lxd/arc-job.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
echo 'PASS: x' > "$TMP/ok.log"; : > "$TMP/none.log"
[ "$(lxd_arc_verdict "$TMP/ok.log" 0)" = PASS ] || fail pass
[ "$(lxd_arc_verdict "$TMP/none.log" 0)" = FAIL_NO_PASS_LINE ] || fail nopass
[ "$(lxd_arc_verdict "$TMP/ok.log" 3)" = FAIL ] || fail rc
# lxd_arc_run end-to-end with a fake arc, slot stubs, real run_bounded
mkdir -p "$TMP/root/test/install-recovery/arcs"
printf '#!/usr/bin/env bash\necho "PASS: fake $1"\n' > "$TMP/root/test/install-recovery/arcs/fake-arc.sh"
printf '#!/usr/bin/env bash\necho started\n' > "$TMP/root/test/install-recovery/arcs/early-arc.sh"
printf '#!/usr/bin/env bash\nexit 7\n' > "$TMP/root/test/install-recovery/arcs/bad-arc.sh"
events=$TMP/events
lxd_slot_acquire() { echo "acquire $2" >> "$events"; LXD_SLOT=3; }
lxd_slot_release() { echo "release $2 $3" >> "$events"; }
export ARC_ROOT=$TMP/root LXD_HOST=fake ARC_TIMEOUT_S=30 ARC_TIMEOUT_GRACE_S=2
v=$(lxd_arc_run fake "$TMP/fake.log" m1) || fail "fake arc not PASS ($v)"
[ "$v" = PASS ] && grep -q 'PASS: fake statbus-arc-fake' "$TMP/fake.log" || fail "fake verdict/log: $v"
v=$(lxd_arc_run early "$TMP/early.log" m1) && fail "early exit passed"; [ "$v" = FAIL_NO_PASS_LINE ] || fail "early: $v"
v=$(lxd_arc_run bad "$TMP/bad.log" m1) && fail "bad passed"; [ "$v" = FAIL ] || fail "bad: $v"
[ "$(grep -c '^release 3 m1' "$events")" = 3 ] || fail "slot not released on every path"
# rc 125 (group not emptied): actual rc preserved, slot stays held, log says so
run_bounded() { return 125; }
: > "$events"
rc=0; v=$(lxd_arc_run fake "$TMP/r125.log" m1) || rc=$?
[ "$rc" = 125 ] && [ "$v" = FAIL ] || fail "125 not preserved: rc=$rc v=$v"
! grep -q '^release' "$events" || fail "slot released while owned group alive"
grep -q 'slot .* held' "$TMP/r125.log" || fail "125 not recorded in log"
source "$ROOT/test/install-recovery/lxd/proc-tree.sh"
lxd_arc_run nope "$TMP/n.log" m1 2>/dev/null && fail "unknown arc ran"
echo 'PASS: shared arc runner claims/releases a slot on every path and never passes an early exit'
