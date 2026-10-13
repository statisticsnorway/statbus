#!/usr/bin/env bash
# STATBUS-488: the prepare path must fetch ops/setup-ubuntu-lts.sh from the
# release being installed, resolved the way install.sh resolves it (an explicit
# tag, or the stable channel via /releases/latest), never from master.
#
# Every operator document that shows the prepare fetch marks it with the line
# "# STATBUS-488 prepare fetch". This test runs each marked snippet against a
# stubbed curl and checks the URL it produces for a named release and for the
# stable channel. It also checks that no prepare fetch in the operator docs
# still names master.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DOCS=(doc/setup-ubuntu-lts.md doc/DEPLOYMENT.md doc/hetzner-bootstrap.md ops/setup-ubuntu-lts.sh)
fail=0
RAW=https://raw.githubusercontent.com/statisticsnorway/statbus

# Stub curl: record every URL; answer the releases API like GitHub does.
CURL_LOG="$(mktemp)"
curl() {
    local a url=""
    for a in "$@"; do [[ "$a" == http* ]] && url="$a"; done
    echo "$url" >> "$CURL_LOG"
    if [[ "$url" == *api.github.com*releases/latest* ]]; then
        printf '{\n  "tag_name": "v2026.09.1",\n}\n'
    fi
    return 0
}
# The channel resolution must be the same call install.sh makes.
API_LATEST='https://api.github.com/repos/statisticsnorway/statbus/releases/latest'
grep -q "curl -sL $API_LATEST" "$ROOT/install.sh" || { echo "FAIL install.sh no longer resolves stable via $API_LATEST"; fail=1; }

for doc in "${DOCS[@]}"; do
    file="$ROOT/$doc"
    if grep -nE 'statbus/(refs/heads/)?master/ops/setup-ubuntu-lts\.sh' "$file"; then
        echo "FAIL $doc still fetches the setup script from master"; fail=1
    fi
    snippet="$(awk '/# STATBUS-488 prepare fetch/{on=1} on{print} on&&/ops\/setup-ubuntu-lts\.sh/{exit}' "$file" | sed -E 's/^#   ?//')"
    if [[ -z "$snippet" ]]; then
        echo "FAIL $doc has no marked prepare fetch"; fail=1; continue
    fi
    grep -q "curl -sL $API_LATEST" <<<"$snippet" || { echo "FAIL $doc does not resolve the channel like install.sh"; fail=1; }
    for mode in named stable; do
        : > "$CURL_LOG"
        ( if [[ $mode == named ]]; then VERSION=v2026.03.0; else unset VERSION; fi
          set +u; eval "$snippet" >/dev/null 2>&1 )
        got="$(tail -1 "$CURL_LOG")"
        if [[ $mode == named ]]; then tag=v2026.03.0; else tag=v2026.09.1; fi
        want="$RAW/$tag/ops/setup-ubuntu-lts.sh"
        if [[ "$got" == "$want" ]]; then echo "PASS $doc $mode -> $got"; else echo "FAIL $doc $mode -> '$got' want '$want'"; fail=1; fi
    done
done
rm -f "$CURL_LOG"
exit $fail
