#!/usr/bin/env bash
# STATBUS-570: statbus.org/rc/<name>.sh runs the newest release candidate's own
# script. The newest is by (year, month, patch, rc), so v2026.11.1-rc.06 beats
# v2026.10.6-rc.12 and a later stable tag is not a candidate. install also
# installs that candidate (--version <tag>); every script gets the operator's
# arguments. With no candidate published the resolver refuses and names the
# stable shortcut. Double: curl answers the releases list and serves each
# release asset as a script that prints how it was called.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/rc-resolver.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
fail=0
pass() { echo "PASS $1"; }
nope() { echo "FAIL $1"; fail=1; }

cat > "$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
out="" url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out=$2; shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
    esac
done
case "$url" in
    https://api.github.com/repos/statisticsnorway/statbus/releases\?per_page=50)
        for tag in $RELEASE_TAGS; do printf '    "tag_name": "%s",\n' "$tag"; done ;;
    https://github.com/statisticsnorway/statbus/releases/download/*)
        rest=${url#https://github.com/statisticsnorway/statbus/releases/download/}
        printf 'echo "ran %s from %s with: $*"\n' "${rest#*/}" "${rest%%/*}" > "$out" ;;
    *) echo "curl double: unexpected $url" >&2; exit 22 ;;
esac
EOF
chmod +x "$work/bin/curl"

run() { # run <resolver> <tags> [args...]
    local resolver=$1 tags=$2
    shift 2
    RELEASE_TAGS=$tags TMPDIR="$work/tmp" PATH="$work/bin:$PATH" bash "$ROOT/ops/rc/$resolver" "$@" </dev/null 2>&1
}
mkdir -p "$work/tmp"

tags="v2026.10.6-rc.12 v2026.11.1-rc.05 v2026.11.1-rc.06 v2026.11.0 v2026.12.0"
check() { # check <name> <expected> <actual>
    if [ "$3" = "$2" ]; then pass "$1"; else nope "$1"; printf '    want: %s\n    got:  %s\n' "$2" "$3"; fi
}
check "install runs the newest candidate's installer and installs it" \
    "ran install.sh from v2026.11.1-rc.06 with: --version v2026.11.1-rc.06 --non-interactive" \
    "$(run install.sh "$tags" --non-interactive)"
check "setup runs the newest candidate's setup script" \
    "ran setup-ubuntu-lts.sh from v2026.11.1-rc.06 with: --only-stages service-account" \
    "$(run setup.sh "$tags" --only-stages service-account)"
check "uninstall runs the newest candidate's uninstaller" \
    "ran uninstall.sh from v2026.11.1-rc.06 with: " \
    "$(run uninstall.sh "$tags")"

out=$(run install.sh "v2026.11.0 v2026.12.0")
rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "No StatBus release candidate is published; https://statbus.org/install.sh serves the latest stable." ]; then
    pass "no candidate is refused with the stable shortcut"
else
    nope "no candidate is refused with the stable shortcut (exit $rc)"
    printf '    %s\n' "$out"
fi

check "the downloaded scripts are removed afterwards" "" "$(ls -A "$work/tmp")"

if [ "$fail" = 0 ]; then echo "rc resolver test: PASS"; else echo "rc resolver test: FAIL"; exit 1; fi
