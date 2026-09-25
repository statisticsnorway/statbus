#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "${STATBUS_CREDENTIALS_FILE:-$ROOT/.env.credentials}"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required}"
export HCLOUD_TOKEN
name=statbus-lxd-fleet
ip=$(hcloud server describe "$name" -o json 2>/dev/null | jq -r '.public_net.ipv4.ip // empty' || true)
if [ -n "$ip" ]; then printf '%s\n' "$ip"; exit 0; fi
hcloud server create --name "$name" --type ccx33 --image ubuntu-24.04 --location hel1 --ssh-key 'jorgen@veridit.no' >/dev/null
ip=$(hcloud server describe "$name" -o json | jq -er '.public_net.ipv4.ip')
opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5)
for ((i=0;i<90;i++)); do
    if ssh "${opts[@]}" "root@$ip" true 2>/dev/null; then break; fi
    if ((i == 89)); then echo 'SSH never became ready' >&2; exit 1; fi
    sleep 2
done
ssh "${opts[@]}" "root@$ip" 'bash -s' <<'REMOTE'
set -euo pipefail
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y btrfs-progs >/dev/null
if ! snap list lxd >/dev/null 2>&1; then snap install lxd >/dev/null; fi
if ! lxc storage show statbus-test >/dev/null 2>&1; then
    cat > /root/lxd-preseed.yml <<'PRESEED'
config: {}
networks:
- name: lxdbr0
  type: bridge
  config:
    ipv4.address: auto
    ipv4.nat: "true"
    ipv6.address: none
storage_pools:
- name: statbus-test
  driver: btrfs
  config:
    size: 60GiB
profiles:
- name: default
  config: {}
  devices:
    root:
      path: /
      pool: statbus-test
      type: disk
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
projects: []
cluster: null
PRESEED
    lxd init --preseed < /root/lxd-preseed.yml
fi
test "$(lxc storage get statbus-test driver)" = btrfs
REMOTE
printf '%s\n' "$ip"
