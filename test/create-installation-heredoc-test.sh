#!/bin/bash
# The remote steps of ops/create-new-statbus-installation.sh are unquoted
# heredocs (<<NAME) so that $VARIABLES from the operator's side expand into
# them. Command substitution expands there too: a backtick pair or $( ) that is
# not escaped runs on the operator's machine while the heredoc is built, and
# its output becomes part of the remote script. This test expands every
# unquoted heredoc with a stub for each command it could reach and asserts the
# expanded text is a valid bash script that ran nothing locally.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/ops/create-new-statbus-installation.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
while IFS=: read -r start name; do
    end=$(awk -v s="$start" -v n="$name" 'NR>s && $0==n {print NR; exit}' "$SCRIPT")
    [ -n "$end" ] || { echo "FAIL: heredoc $name at line $start has no terminator"; fail=1; continue; }
    probe="$TMP/$name.probe.sh"
    expanded="$TMP/$name.expanded.sh"
    {
        # Any command the operator side could run while expanding is recorded.
        echo 'command_not_found_handle() { echo "LOCAL-RAN:$*" >>"'"$TMP"'/ran"; }'
        echo 'for c in sb git grep sed cut awk docker sudo ls; do eval "$c() { echo LOCAL-RAN:$c \"\$*\" >>\"'"$TMP"'/ran\"; }"; done'
        echo "cat > '$expanded' <<$name"
        sed -n "$((start + 1)),${end}p" "$SCRIPT"
    } >"$probe"
    rm -f "$TMP/ran"
    bash "$probe" >/dev/null 2>&1 || true
    if [ -s "$TMP/ran" ]; then
        echo "FAIL: heredoc $name (line $start) runs commands on the operator's machine: $(tr '\n' ' ' <"$TMP/ran")"
        fail=1
    fi
    if ! bash -n "$expanded" 2>"$TMP/syntax"; then
        echo "FAIL: heredoc $name (line $start) expands to invalid bash: $(head -1 "$TMP/syntax")"
        fail=1
    fi
done < <(grep -nE '<< ?[A-Z_]+$' "$SCRIPT" | sed -E 's/^([0-9]+):.*<< ?([A-Z_]+)$/\1:\2/')

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "create-installation heredoc tests: PASS"
