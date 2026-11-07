#!/usr/bin/env bash
# STATBUS-588: the maintenance block of each serving Caddy template, run by
# real Caddy. With /statbus-maintenance/active present every page answers 503
# with the maintenance page while /monitor is left to its own route; without
# the marker pages answer normally. The block is taken verbatim from the
# template, so the test exercises the shipped matcher, not a copy of it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${CADDY_TEST_IMAGE:-caddy:2}"
work="$(mktemp -d "${TMPDIR:-/tmp}/caddy-maint.XXXXXX")"
trap 'docker rm -f caddy-maint-test >/dev/null 2>&1; rm -rf "$work"' EXIT
fail=0

for template in standalone private; do
    block="$(awk '/^    @maintenance \{/{p=1} p{print} p&&/^    \}$/{n++} n==2{exit}' "$ROOT/caddy/templates/$template.caddyfile.tmpl")"
    [ -n "$block" ] || { echo "FAIL $template: no @maintenance block"; fail=1; continue; }
    mkdir -p "$work/$template/maint" "$work/$template/page"
    echo "statbus maintenance page" > "$work/$template/page/maintenance.html"
    cat > "$work/$template/Caddyfile" <<EOF
:80 {
    handle /monitor {
        respond "monitor" 200
    }
$block
    respond "app" 200
}
EOF
    docker rm -f caddy-maint-test >/dev/null 2>&1
    if ! docker run -d --name caddy-maint-test -p 127.0.0.1:18588:80 \
        -v "$work/$template/Caddyfile:/etc/caddy/Caddyfile:ro" \
        -v "$work/$template/maint:/statbus-maintenance" \
        -v "$work/$template/page:/maintenance-page:ro" \
        "$IMAGE" >/dev/null; then
        echo "FAIL $template: caddy did not start"; fail=1; continue
    fi
    for _ in $(seq 1 30); do curl -s -o /dev/null 127.0.0.1:18588/ && break; sleep 0.5; done
    check() { # label path want-status [want-body]
        local body status
        body="$(curl -s -w '\n%{http_code}' "127.0.0.1:18588$2")"
        status="${body##*$'\n'}"; body="${body%$'\n'*}"
        if [ "$status" = "$3" ] && { [ -z "${4:-}" ] || grep -q "$4" <<<"$body"; }; then
            echo "PASS $template $1: $2 -> $status"
        else
            echo "FAIL $template $1: $2 -> $status (want $3${4:+ with '$4'}) body: $body"; fail=1
        fi
    }
    check "no marker" / 200 app
    check "no marker" /login 200 app
    touch "$work/$template/maint/active"
    check "marker" / 503 "statbus maintenance page"
    check "marker" /login 503 "statbus maintenance page"
    check "marker" /monitor 200 monitor
    rm -f "$work/$template/maint/active"
    check "marker removed" / 200 app
    docker rm -f caddy-maint-test >/dev/null 2>&1
done

if [ "$fail" = 0 ]; then echo "caddy maintenance route test: PASS"; else echo "caddy maintenance route test: FAIL"; exit 1; fi
