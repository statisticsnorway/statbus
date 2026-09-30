#!/usr/bin/env bash
# Runs ON the fleet host under /root/fleet-run.lock (reap.sh). Removes what a
# killed job left behind, so the reaper is not blind forever to it:
#   * markers older than STALE_S (their EXIT trap never ran)
#   * s2-<tag>-<scenario> forks older than STALE_S (never s2-base-*/fleet-base-*,
#     which are catalog checkpoints, not job forks)
# Selector is pure (stdin "name epoch" -> names) so it is testable offline.
set -euo pipefail
stale=${LXD_STALE_S:-14400}
now=${FLEET_NOW:-$(date +%s)}
orphan_forks() {
    local name created
    while read -r name created; do
        [[ "$name" =~ ^s2- ]] || continue
        [[ "$name" =~ ^s2-base- ]] && continue
        [[ "$created" =~ ^[0-9]+$ ]] || continue
        [ $((now - created)) -ge "$stale" ] && printf '%s\n' "$name"
    done
}
if [ "${1:-}" = --select ]; then orphan_forks; exit 0; fi
act=${FLEET_ACTIVE_DIR:-/root/fleet-active}
if [ -d "$act" ]; then
    for f in "$act"/*; do
        [ -e "$f" ] || continue
        mt=$(stat -c %Y "$f")
        if [ $((now - mt)) -ge "$stale" ]; then echo "sweep stale marker ${f##*/}"; rm -f "$f"; fi
    done
fi
for n in $(lxc list -c n --format csv); do
    created=$(lxc info "$n" | sed -n 's/^Created: //p' | head -n1)
    epoch=$(date -d "$created" +%s 2>/dev/null || true)
    printf '%s %s\n' "$n" "$epoch"
done | orphan_forks | while read -r n; do
    echo "sweep orphan fork $n"; lxc delete "$n" --force || true
done
