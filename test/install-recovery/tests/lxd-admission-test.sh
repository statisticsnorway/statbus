#!/usr/bin/env bash
# Offline contract for ops/lxd-fleet/{admission,fleet-busy,fleet-sweep}.sh
# (STATBUS-425 M4). Runs the REAL scripts against a tmpdir host stand-in.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export FLEET_ACTIVE_DIR=$TMP/active FLEET_SLOT_DIR=$TMP/slots FLEET_HARDENING=$TMP/hardening
mkdir -p "$FLEET_ACTIVE_DIR"
source "$ROOT/ops/lxd-fleet/marker.sh"
source "$ROOT/ops/lxd-fleet/admission.sh"
flock() { shift 1; "$@"; }; export -f flock
_lxd_marker_ssh() { shift 5; bash -c "$1"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

id=$(GITHUB_RUN_ID=77 lxd_marker_id v2026.09.3-rc.17 faultfleet)
[[ "$id" == v2026-09-3-rc-17.77-faultfleet-* ]] || fail "marker id $id"
lxd_marker_id v2026.09.3-rc.17 'bad job' 2>/dev/null && fail "invalid job accepted"

# slots: bounded, owner-marker required, orphan slot reclaimable
LXD_HOST_SLOTS=2
touch "$FLEET_ACTIVE_DIR/a" "$FLEET_ACTIVE_DIR/b" "$FLEET_ACTIVE_DIR/c"
lxd_slot_acquire h a 0; sa=$LXD_SLOT
lxd_slot_acquire h b 0; sb=$LXD_SLOT
[ "$sa" != "$sb" ] || fail "two owners got one slot"
lxd_slot_acquire h c 0 2>/dev/null && fail "third slot granted beyond capacity"
lxd_slot_release h "$sa" a
lxd_slot_acquire h c 0; [ "$LXD_SLOT" = "$sa" ] || fail "released slot not reused"
rm -f "$FLEET_ACTIVE_DIR/b"   # owner b died/swept: its slot is orphaned
touch "$FLEET_ACTIVE_DIR/d"
lxd_slot_acquire h d 0; [ "$LXD_SLOT" = "$sb" ] || fail "orphaned slot not reclaimed"
lxd_slot_acquire h ghost 0 2>/dev/null && fail "slot granted to owner without marker"
lxd_slot_release h 1 wrongowner; [ -e "$FLEET_SLOT_DIR/1" ] || fail "release by non-owner freed slot"
echo 'PASS: slots are bounded, owner-scoped and orphan-reclaimable'

# fleet-busy: siblings do not block, foreign candidates and hardening do, stale ignored
rm -rf "$FLEET_ACTIVE_DIR"; mkdir -p "$FLEET_ACTIVE_DIR"
export LXC_LIST_CMD="printf 's2-v2026-09-3-rc-17-x,RUNNING\ns2-base-v2026-09-3-rc-17-hardened-nothing-installed,STOPPED\n'"
touch "$FLEET_ACTIVE_DIR/v2026-09-3-rc-17.1-arcs-9"
bash "$ROOT/ops/lxd-fleet/fleet-busy.sh" v2026-09-3-rc-17 >/dev/null || fail "sibling job treated as busy"
touch "$FLEET_ACTIVE_DIR/v2026-09-3-rc-16.1-arcs-9"
bash "$ROOT/ops/lxd-fleet/fleet-busy.sh" v2026-09-3-rc-17 >/dev/null && fail "older candidate marker ignored"
FLEET_NOW=$(( $(date +%s) + 100000 )) bash "$ROOT/ops/lxd-fleet/fleet-busy.sh" v2026-09-3-rc-17 >/dev/null || fail "stale marker blocked"
rm "$FLEET_ACTIVE_DIR/v2026-09-3-rc-16.1-arcs-9"
export LXC_LIST_CMD="printf 's2-v2026-09-3-rc-16-x,RUNNING\n'"
bash "$ROOT/ops/lxd-fleet/fleet-busy.sh" v2026-09-3-rc-17 >/dev/null && fail "foreign running guest ignored"
export LXC_LIST_CMD="printf ''"
touch "$FLEET_HARDENING"
bash "$ROOT/ops/lxd-fleet/fleet-busy.sh" v2026-09-3-rc-17 >/dev/null && fail "hardening ignored"
rm -f "$FLEET_HARDENING"
echo 'PASS: fleet-busy waits only for foreign candidates/hardening, not siblings or stale markers'

# fleet-sweep selector: only old s2-* forks, never bases
sel=$(FLEET_NOW=100000 LXD_STALE_S=1000 bash "$ROOT/ops/lxd-fleet/fleet-sweep.sh" --select <<'IN'
s2-v2026-09-3-rc-17-old 1000
s2-v2026-09-3-rc-17-new 99500
s2-base-v2026-09-3-rc-17-hardened-nothing-installed 1000
fleet-base-v2026-09-3-rc-17 1000
other 1000
s2-v2026-09-3-rc-17-noepoch
IN
)
[ "$sel" = s2-v2026-09-3-rc-17-old ] || fail "sweep selected: $sel"
echo 'PASS: orphan sweep selects only aged job forks'
