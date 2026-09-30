#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1090
source "${STATBUS_CREDENTIALS_FILE:-$ROOT/.env.credentials}"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN required}"
export HCLOUD_TOKEN
name=statbus-lxd-fleet
ip=$(hcloud server describe "$name" -o json | jq -er '.public_net.ipv4.ip')
opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
# The persistent reap marker closes the check/delete race. Fleet starters must
# refuse /root/fleet-reaping and hold flock on /root/fleet-run.lock.
# "Active" is directory-non-empty: smoke, the fault driver and arc jobs each
# hold their OWN marker file under /root/fleet-active/ concurrently
# (STATBUS-425 M2'); a single marker file would let the first job to finish
# delete the file while a sibling job is still genuinely running.
# Sweep what killed jobs left (markers/forks older than LXD_STALE_S, default 4h,
# above every job timeout) so a dead job cannot block reaping forever. Touches
# nothing younger, so it is safe at any time.
ssh "${opts[@]}" "root@$ip" 'flock -n /root/fleet-run.lock bash -s' < "$ROOT/ops/lxd-fleet/fleet-sweep.sh" || true
ssh "${opts[@]}" "root@$ip" 'flock -n /root/fleet-run.lock bash -s' <<'REMOTE'
set -euo pipefail
marker=/root/last-fleet-activity
[ -f "$marker" ] || { echo 'REFUSE: activity marker missing' >&2; exit 1; }
read -r last < "$marker"
[[ "$last" =~ ^[0-9]+$ ]] || { echo 'REFUSE: invalid activity marker' >&2; exit 1; }
now=$(date +%s)
(( now >= last + 10800 )) || { echo 'REFUSE: fleet active within three hours' >&2; exit 42; }
active=$(ls -A /root/fleet-active 2>/dev/null || true)
[ -z "$active" ] || { echo "REFUSE: fleet jobs active: $active" >&2; exit 1; }
[ ! -e /root/fleet-hardening.active ] || { echo 'REFUSE: host hardening is active' >&2; exit 1; }
[ ! -e /root/fleet-reaping ] || { echo 'REFUSE: reap already underway' >&2; exit 1; }
# review H3: the marker directory and the 3h timestamp are both
# process-level bookkeeping - either can go stale (a crashed job whose EXIT
# trap never ran, a marker released early by a bug) while a real LXD guest
# is still RUNNING underneath it. Check the actual guest state directly as
# the last, most concrete guard before this box is deleted.
guests=$(lxc list --format csv)
! grep -q RUNNING <<< "$guests" || { echo 'REFUSE: LXD guest still running' >&2; exit 1; }
touch /root/fleet-reaping
REMOTE
if ! hcloud server delete "$name"; then
    ssh "${opts[@]}" "root@$ip" 'rm -f /root/fleet-reaping' || true
    exit 1
fi
