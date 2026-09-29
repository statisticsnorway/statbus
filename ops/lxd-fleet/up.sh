#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "${STATBUS_CREDENTIALS_FILE:-$ROOT/.env.credentials}"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required}"
export HCLOUD_TOKEN
name=statbus-lxd-fleet
image=ubuntu-26.04
# Resolve the canonical image ID before touching an existing box. Refuse an
# unavailable target rather than deleting a working host and discovering the
# missing image afterward.
image_id=$(hcloud image describe "$image" -o json | jq -er '.id')
opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5)
server=$(hcloud server describe "$name" -o json 2>/dev/null || true)
# A same-name machine is not automatically ours.
if [ -n "$server" ]; then
    [ "$(jq -r '.labels["statbus-purpose"] // empty' <<<"$server")" = lxd-fleet ] || { echo 'REFUSE: foreign or unlabeled fleet box' >&2; exit 1; }
    [ "$(jq -r '.server_type.name // empty' <<<"$server")" = ccx33 ] || { echo 'REFUSE: unexpected server type' >&2; exit 1; }
    current_image=$(jq -r '.image.id // empty' <<<"$server")
    if [ "$current_image" != "$image_id" ]; then
        old_ip=$(jq -er '.public_net.ipv4.ip' <<<"$server")
        echo "IMAGE DRIFT: fleet box image ID $current_image != $image ID $image_id; deleting and recreating $name (snapshots intentionally disposable)" >&2
        # Same lock/sentinel protocol as reap.sh. An active fork or a running
        # orphan is NOT a disposable idle base: refuse and let the operator
        # inspect it, rather than destroying an in-progress proof. "Active" is
        # directory-non-empty: smoke, the fault driver and arc jobs each hold
        # their OWN marker file under /root/fleet-active/ concurrently
        # (STATBUS-425 M2').
        ssh "${opts[@]}" "root@$old_ip" 'flock -n /root/fleet-run.lock bash -s' <<'REMOTE'
set -euo pipefail
active=$(ls -A /root/fleet-active 2>/dev/null || true)
[ -z "$active" ] && [ ! -e /root/fleet-hardening.active ] && [ ! -e /root/fleet-reaping ] || { echo 'REFUSE: fleet, hardening or reaper active' >&2; exit 1; }
guests=$(lxc list --format csv)
! grep -q RUNNING <<< "$guests" || { echo 'REFUSE: LXD guest still running' >&2; exit 1; }
touch /root/fleet-reaping
REMOTE
        if ! hcloud server delete "$name"; then
            ssh "${opts[@]}" "root@$old_ip" 'rm -f /root/fleet-reaping' || true
            exit 1
        fi
        server=""
    fi
fi
if [ -z "$server" ]; then
    # Both keys at creation: the operator's, and the CI key whose private half
    # is the LXD_FLEET_SSH_KEY secret. Without the CI key a freshly created box
    # is unreachable from the workflow (the prototype only worked because the
    # key had been appended by hand).
    hcloud server create --name "$name" --type ccx33 --image "$image" --location hel1 --ssh-key 'jorgen@veridit.no' --ssh-key statbus-lxd-fleet-ci --label statbus-purpose=lxd-fleet >/dev/null
    server=$(hcloud server describe "$name" -o json)
fi
[ "$(jq -r '.labels["statbus-purpose"] // empty' <<<"$server")" = lxd-fleet ] || { echo 'REFUSE: foreign or unlabeled fleet box' >&2; exit 1; }
[ "$(jq -r '.server_type.name // empty' <<<"$server")" = ccx33 ] || { echo 'REFUSE: unexpected server type' >&2; exit 1; }
[ "$(jq -er '.image.id' <<<"$server")" = "$image_id" ] || { echo "REFUSE: box did not boot $image" >&2; exit 1; }
ip=$(jq -er '.public_net.ipv4.ip' <<<"$server")
for ((i=0;i<90;i++)); do
    if ssh "${opts[@]}" "root@$ip" true 2>/dev/null; then break; fi
    if ((i == 89)); then echo 'SSH never became ready' >&2; exit 1; fi
    sleep 2
done
ssh "${opts[@]}" "root@$ip" 'bash -s' <<'REMOTE'
set -euo pipefail
# This script arrives on stdin (bash -s). lxc create/add commands read YAML
# from a non-terminal stdin, so each one gets </dev/null or it swallows the
# remainder of this script ("yaml: mapping values are not allowed").
if ! command -v btrfs >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y btrfs-progs </dev/null >/dev/null
fi
if ! snap list lxd >/dev/null 2>&1; then snap install lxd </dev/null >/dev/null; fi
if ! lxc storage show statbus-test >/dev/null 2>&1; then
    lxc storage create statbus-test btrfs size=60GiB </dev/null
fi
if ! lxc network show lxdbr0 >/dev/null 2>&1; then
    lxc network create lxdbr0 ipv4.address=auto ipv4.nat=true ipv6.address=none </dev/null
fi
# `driver` is a pool attribute, not a config key: `lxc storage get <pool>
# driver` prints nothing (observed on LXD 5.21 / Ubuntu 26.04), so read it
# from the listing instead.
[ "$(lxc storage list --format csv | awk -F, '$1 == "statbus-test" {print $2}')" = btrfs ] || { echo 'REFUSE: storage pool is not btrfs' >&2; exit 1; }
[ "$(lxc network get lxdbr0 ipv4.nat)" = true ] || { echo 'REFUSE: bridge NAT is disabled' >&2; exit 1; }
[ "$(lxc network get lxdbr0 ipv6.address)" = none ] || { echo 'REFUSE: bridge IPv6 differs' >&2; exit 1; }
# `device show` emits top-level keys; `device get` both checks and stays quiet
# when the device already exists (review round 2: indented-key grep missed).
[ "$(lxc profile device get default root pool 2>/dev/null)" = statbus-test ] || lxc profile device add default root disk path=/ pool=statbus-test </dev/null
[ "$(lxc profile device get default eth0 network 2>/dev/null)" = lxdbr0 ] || lxc profile device add default eth0 nic name=eth0 network=lxdbr0 </dev/null
[ "$(lxc profile device get default root pool)" = statbus-test ] || { echo 'REFUSE: default profile uses another pool' >&2; exit 1; }
[ "$(lxc profile device get default eth0 network)" = lxdbr0 ] || { echo 'REFUSE: default profile uses another bridge' >&2; exit 1; }
REMOTE
# Host security is part of the ramp, not an optional follow-up. In particular,
# never change sshd/UFW while a fleet is executing on this host. The new SSH
# connection in harden-host.sh verifies the key before and after each change.
#
# review B4: harden-host.sh REFUSES while any guest is RUNNING or any starter
# holds the marker directory (by design - it must never touch sshd/UFW mid-
# fleet). Calling it unconditionally on every up.sh invocation therefore made
# EVERY concurrent consumer after the first fail: rc.N+1's smoke ramping
# while rc.N's fault fleet or arcs are still running on the SAME box hit this
# refusal, a genuine regression against the single-tenant Hetzner smoke this
# replaces. Harden only when this box is genuinely new to this image - a
# fresh create or a just-completed image-drift recreate, both of which leave
# NO prior /root/fleet-hardened-<marker_id> marker because the box (or its
# prior marker set) did not exist a moment ago. An existing, already-hardened
# box for the SAME image AND the SAME harden-host.sh content is a pure IP
# resolution for every later consumer.
#
# review M-B4: keying the marker on image_id ALONE made a harden-host.sh edit
# (this series' own MaxStartups 30:30:100 addition) invisible to an existing
# warm box until an unrelated image drift or reap recreated it - the marker
# would keep matching even though the box's actual sshd config had drifted
# from what the CURRENT harden-host.sh would produce. Fold the script's own
# content hash into the marker identity so a content change forces one more
# hardening pass on the next ramp, exactly like an image change already does.
harden_hash=$(sha256sum "$ROOT/ops/lxd-fleet/harden-host.sh" | cut -d' ' -f1)
harden_marker="/root/fleet-hardened-$image_id-$harden_hash"
if ssh "${opts[@]}" "root@$ip" "test -e $harden_marker"; then
    echo "Fleet host already hardened for image $image_id at harden-host.sh $harden_hash; skipping (review B4/M-B4)" >&2
else
    "$ROOT/ops/lxd-fleet/harden-host.sh" "root@$ip"
    ssh "${opts[@]}" "root@$ip" "touch $harden_marker"
fi
# review H4: reap.sh's cron can fire between this ramp job finishing and the
# NEXT job (a smoke leg, the fault driver, an arc matrix job) acquiring its
# own marker under /root/fleet-active/ - up.sh itself never stamped
# /root/last-fleet-activity, so a box idle for close to 3h at ramp time could
# be deleted by the reaper in that runner-pickup-plus-checkout window before
# anyone holds a marker. Stamp activity as this ramp's last act so the
# reaper's 3h clock restarts here, same as every other starter already does.
ssh "${opts[@]}" "root@$ip" 'date +%s > /root/last-fleet-activity'
printf '%s\n' "$ip"
