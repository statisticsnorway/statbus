#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "${STATBUS_CREDENTIALS_FILE:-$ROOT/.env.credentials}"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN required}"
export HCLOUD_TOKEN
name=statbus-lxd-fleet
ip=$(hcloud server describe "$name" -o json | jq -er '.public_net.ipv4.ip')
opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
# The persistent reap marker closes the check/delete race. Fleet starters must
# refuse /root/fleet-reaping and hold flock on /root/fleet-run.lock.
ssh "${opts[@]}" "root@$ip" 'flock -n /root/fleet-run.lock bash -s' <<'REMOTE'
set -euo pipefail
marker=/root/last-fleet-activity
[ -f "$marker" ] || { echo 'REFUSE: activity marker missing' >&2; exit 1; }
read -r last < "$marker"
[[ "$last" =~ ^[0-9]+$ ]] || { echo 'REFUSE: invalid activity marker' >&2; exit 1; }
now=$(date +%s)
(( now >= last + 10800 )) || { echo 'REFUSE: fleet active within three hours' >&2; exit 1; }
[ ! -e /root/fleet-run.active ] || { echo 'REFUSE: fleet run marker exists' >&2; exit 1; }
[ ! -e /root/fleet-reaping ] || { echo 'REFUSE: reap already underway' >&2; exit 1; }
touch /root/fleet-reaping
REMOTE
if ! hcloud server delete "$name"; then
    ssh "${opts[@]}" "root@$ip" 'rm -f /root/fleet-reaping' || true
    exit 1
fi
