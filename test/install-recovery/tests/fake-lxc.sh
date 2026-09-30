# shellcheck shell=bash
# Offline fake LXD host for the M4 lifecycle tests (SYNTHETIC: not a real host).
# Creates a fake lxc/flock/date environment under $1. Store = $1/store.
# lxc: info, copy (-c k=v), config get/set, snapshot, delete, start/stop/exec no-ops.
# FAKE_COPY_CONFIG_FAIL=1 -> `lxc copy ... -c` fails before creating anything.
mk_fake_env() {
  local d=$1; mkdir -p "$d/bin" "$d/store" "$d/root/fleet-active"
  cat > "$d/bin/lxc" <<'LX'
#!/usr/bin/env bash
S=${FAKE_STORE:?}
case "$1" in
  info) [ -d "$S/$2" ] || exit 1
        echo "Name: $2"; echo "Created: $(cat "$S/$2/created" 2>/dev/null || echo '2026/09/30 10:00 UTC')"
        [ -e "$S/$2/snap" ] && echo '| checkpoint          | x |' ; exit 0 ;;
  copy) src=${2%/checkpoint}; dst=$3; shift 3; cfg=()
        while [ $# -gt 0 ]; do [ "$1" = -c ] && { cfg+=("$2"); shift 2; } || shift; done
        [ -e "$S/$src/snap" ] || exit 1; [ ! -d "$S/$dst" ] || { echo "already exists" >&2; exit 1; }
        [ "${FAKE_COPY_CONFIG_FAIL:-0}" = 1 ] && [ ${#cfg[@]} -gt 0 ] && { echo "config rejected" >&2; exit 1; }
        mkdir -p "$S/$dst"; cp -R "$S/$src/." "$S/$dst/"; rm -f "$S/$dst/snap"; date -u +'%Y/%m/%d %H:%M UTC' > "$S/$dst/created"
        for c in ${cfg[@]+"${cfg[@]}"}; do printf '%s' "${c#*=}" > "$S/$dst/${c%%=*}"; done; exit 0 ;;
  config) if [ "$2" = get ]; then cat "$S/$3/$4" 2>/dev/null; exit 0; else printf '%s' "$5" > "$S/$3/$4"; exit 0; fi ;;
  snapshot) touch "$S/$2/snap" ;;
  delete) rm -rf "${S:?}/$2" ;;
  list) for n in "$S"/*; do [ -d "$n" ] && echo "${n##*/},$( [ -e "$n/running" ] && echo RUNNING || echo STOPPED)"; done ;;
  exec) if [[ "$*" == *rev-parse* ]]; then cat "$S/$2/HEAD" 2>/dev/null; fi; exit 0 ;;
  *) exit 0 ;;
esac
LX
  printf '#!/usr/bin/env bash\nshift; exec "$@"\n' > "$d/bin/flock"
  # GNU-date shim for `date -d "YYYY/MM/DD HH:MM UTC" +%s` on macOS runners
  cat > "$d/bin/date" <<'DT'
#!/usr/bin/env bash
if [ "${1:-}" = -u ] && [ "${2:-}" = -d ]; then exec python3 -c 'import sys,calendar,time;print(calendar.timegm(time.strptime(sys.argv[1].replace(" UTC",""),"%Y/%m/%d %H:%M")))' "$3"; fi
if [ "${1:-}" = -d ]; then exec python3 -c 'import sys,calendar,time;print(calendar.timegm(time.strptime(sys.argv[1].replace(" UTC",""),"%Y/%m/%d %H:%M")))' "$2"; fi
exec /bin/date "$@"
DT
  chmod +x "$d/bin/"*
  export FAKE_STORE="$d/store" PATH="$d/bin:$PATH"
}
