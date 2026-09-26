#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "${STATBUS_CREDENTIALS_FILE:-$ROOT/.env.credentials}"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required}"
export HCLOUD_TOKEN
name=statbus-lxd-fleet
server=$(hcloud server describe "$name" -o json 2>/dev/null || true)
if [ -z "$server" ]; then
    hcloud server create --name "$name" --type ccx33 --image ubuntu-24.04 --location hel1 --ssh-key 'jorgen@veridit.no' --label statbus-purpose=lxd-fleet >/dev/null
    server=$(hcloud server describe "$name" -o json)
fi
# A same-name machine is not automatically ours.
[ "$(jq -r '.labels["statbus-purpose"] // empty' <<<"$server")" = lxd-fleet ] || { echo 'REFUSE: foreign or unlabeled fleet box' >&2; exit 1; }
[ "$(jq -r '.server_type.name // empty' <<<"$server")" = ccx33 ] || { echo 'REFUSE: unexpected server type' >&2; exit 1; }
ip=$(jq -er '.public_net.ipv4.ip' <<<"$server")
opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5)
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
printf '%s\n' "$ip"
