#!/usr/bin/env bash
# Runs ON the fleet host (ssh root@host bash -s -- SAFE_TAG < fleet-busy.sh).
# Exit 0 = nothing belonging to a DIFFERENT candidate is live; exit 1 = busy.
# This is drain-to-zero narrowed to "do not start behind another candidate":
# the same candidate's smoke/faults/arcs are siblings, not something to wait for.
# Live = a marker younger than STALE_S, or a RUNNING guest whose name is not
# this candidate's fork/base. Stale markers are ignored (a killed job).
set -euo pipefail
safe=${1:?safe tag}
act=${FLEET_ACTIVE_DIR:-/root/fleet-active}
stale=${LXD_STALE_S:-14400}
now=${FLEET_NOW:-$(date +%s)}
busy=0
if [ -d "$act" ]; then
    for f in "$act"/*; do
        [ -e "$f" ] || continue
        id=${f##*/}
        mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
        [ $((now - mt)) -lt "$stale" ] || continue
        case "$id" in "$safe".*) ;; *) echo "foreign marker: $id"; busy=1 ;; esac
    done
fi
[ ! -e "${FLEET_HARDENING:-/root/fleet-hardening.active}" ] || { echo "hardening active"; busy=1; }
guests=$(eval "${LXC_LIST_CMD:-lxc list -c ns --format csv}")
while IFS=, read -r name state; do
    [ "$state" = RUNNING ] || continue
    if [[ ! "$name" =~ ^(s2|s2-base|fleet-base)-${safe}(-|$) ]]; then echo "foreign guest: $name"; busy=1; fi
done <<< "$guests"
[ "$busy" -eq 0 ]
