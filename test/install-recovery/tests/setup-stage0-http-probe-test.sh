#!/usr/bin/env bash
# STATBUS-493: Stage 0 of ops/setup-ubuntu-lts.sh decides by probing, not by
# asking. HTTP reachable -> no question, nothing rewritten. HTTP blocked ->
# the finding is stated and the only question has default yes. curl is
# stubbed so no network is needed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/ops/setup-ubuntu-lts.sh"
fail=0

run_case() { # $1 = "ok" or "blocked"
  HOME="$(mktemp -d)" SUDO_USER="" HTTP_CASE="$1" bash -c '
    source "$1"
    NON_INTERACTIVE=false
    curl() { local u; for u in "$@"; do :; done
      [[ "$u" == http://* && "$HTTP_CASE" == blocked ]] && return 28; return 0; }
    # Decline at the prompt so the blocked case stops before touching /etc.
    ask_yes_no() { echo "ASKED[$1|default=${2:-n}]"; return 1; }
    stage_https_sources
  ' stage0-test "$SCRIPT" 2>&1
}

out="$(run_case ok)"
if ! grep -q "ASKED" <<<"$out" && grep -qi "HTTP.*reachable" <<<"$out"; then
  echo "PASS http-reachable: no question, finding printed: $(grep -i 'HTTP.*reachable' <<<"$out" | head -1)"
else
  echo "FAIL http-reachable case:"; echo "$out"; fail=1
fi

out="$(run_case blocked)"
if grep -q "ASKED\[.*|default=y\]" <<<"$out" && grep -qi "HTTP.*blocked" <<<"$out"; then
  echo "PASS http-blocked: finding stated, asked with default yes: $(grep ASKED <<<"$out")"
else
  echo "FAIL http-blocked case:"; echo "$out"; fail=1
fi
exit $fail
