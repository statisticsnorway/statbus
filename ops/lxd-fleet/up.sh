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
        # inspect it, rather than destroying an in-progress proof.
        ssh "${opts[@]}" "root@$old_ip" 'flock -n /root/fleet-run.lock bash -s' <<'REMOTE'
set -euo pipefail
[ ! -e /root/fleet-run.active ] && [ ! -e /root/fleet-hardening.active ] && [ ! -e /root/fleet-reaping ] || { echo 'REFUSE: fleet, hardening or reaper active' >&2; exit 1; }
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
    hcloud server create --name "$name" --type ccx33 --image "$image" --location hel1 --ssh-key 'jorgen@veridit.no' --label statbus-purpose=lxd-fleet >/dev/null
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
if ! command -v btrfs >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y btrfs-progs >/dev/null
fi
if ! snap list lxd >/dev/null 2>&1; then snap install lxd >/dev/null; fi
if ! lxc storage show statbus-test >/dev/null 2>&1; then
    lxc storage create statbus-test btrfs size=60GiB
fi
if ! lxc network show lxdbr0 >/dev/null 2>&1; then
    lxc network create lxdbr0 ipv4.address=auto ipv4.nat=true ipv6.address=none
fi
[ "$(lxc storage get statbus-test driver)" = btrfs ] || { echo 'REFUSE: storage pool is not btrfs' >&2; exit 1; }
[ "$(lxc network get lxdbr0 ipv4.nat)" = true ] || { echo 'REFUSE: bridge NAT is disabled' >&2; exit 1; }
[ "$(lxc network get lxdbr0 ipv6.address)" = none ] || { echo 'REFUSE: bridge IPv6 differs' >&2; exit 1; }
# `device show` emits top-level keys; `device get` both checks and stays quiet
# when the device already exists (review round 2: indented-key grep missed).
[ "$(lxc profile device get default root pool 2>/dev/null)" = statbus-test ] || lxc profile device add default root disk path=/ pool=statbus-test
[ "$(lxc profile device get default eth0 network 2>/dev/null)" = lxdbr0 ] || lxc profile device add default eth0 nic name=eth0 network=lxdbr0
[ "$(lxc profile device get default root pool)" = statbus-test ] || { echo 'REFUSE: default profile uses another pool' >&2; exit 1; }
[ "$(lxc profile device get default eth0 network)" = lxdbr0 ] || { echo 'REFUSE: default profile uses another bridge' >&2; exit 1; }
REMOTE
# Host security is part of the ramp, not an optional follow-up. In particular,
# never change sshd/UFW while a fleet is executing on this host. The new SSH
# connection in harden-host.sh verifies the key before and after each change.
"$ROOT/ops/lxd-fleet/harden-host.sh" "root@$ip"
printf '%s\n' "$ip"
