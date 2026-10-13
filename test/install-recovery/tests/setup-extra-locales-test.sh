#!/bin/bash
# STATBUS-489: the operator's EXTRA_LOCALES must be enabled whether typed with or
# without a .UTF-8 suffix, and declaring nb_NO must make the macOS-forwarded
# no_NO.UTF-8 resolve (via locale.alias) without overriding an existing alias.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIX=$(mktemp -d); trap 'rm -rf "$FIX"' EXIT
log() { echo "LOG $*"; }; log_warn() { echo "WARN $*"; }
eval "$(sed -n '/^enable_extra_locales() {$/,/^}$/p' "$REPO_ROOT/ops/setup-ubuntu-lts.sh")"
type enable_extra_locales >/dev/null 2>&1 || { echo "FAIL enable_extra_locales() not found in setup-ubuntu-lts.sh"; exit 1; }
fail=0
printf '# en_US.UTF-8 UTF-8\n# nb_NO.UTF-8 UTF-8\n# sq_AL.UTF-8 UTF-8\n' > "$FIX/locale.gen"
printf 'norwegian nb_NO.ISO-8859-1\n' > "$FIX/locale.alias"
out=$(enable_extra_locales "nb_NO.UTF-8 sq_AL" "$FIX/locale.gen" "$FIX/locale.alias")
echo "$out"
grep -q '^nb_NO.UTF-8 UTF-8$' "$FIX/locale.gen" && echo "PASS nb_NO.UTF-8 (typed with suffix) enabled" || { echo "FAIL nb_NO.UTF-8 not enabled"; fail=1; }
grep -q '^sq_AL.UTF-8 UTF-8$' "$FIX/locale.gen" && echo "PASS sq_AL enabled" || { echo "FAIL sq_AL not enabled"; fail=1; }
grep -q 'not found' <<<"$out" && { echo "FAIL spurious not-found warning"; fail=1; } || echo "PASS no spurious not-found warning"
grep -q '^no_NO.UTF-8 nb_NO.UTF-8$' "$FIX/locale.alias" && echo "PASS no_NO.UTF-8 aliased to nb_NO.UTF-8" || { echo "FAIL no_NO.UTF-8 alias missing"; fail=1; }
enable_extra_locales "nb_NO" "$FIX/locale.gen" "$FIX/locale.alias" >/dev/null
[ "$(grep -c '^no_NO.UTF-8' "$FIX/locale.alias")" = 1 ] && echo "PASS rerun is idempotent" || { echo "FAIL alias duplicated"; fail=1; }
printf 'no_NO.UTF-8 nn_NO.UTF-8\n' > "$FIX/locale.alias"
enable_extra_locales "nb_NO" "$FIX/locale.gen" "$FIX/locale.alias" >/dev/null
grep -qx 'no_NO.UTF-8 nn_NO.UTF-8' "$FIX/locale.alias" && [ "$(wc -l < "$FIX/locale.alias")" -eq 1 ] && echo "PASS operator's own no_NO alias untouched" || { echo "FAIL operator alias overridden"; fail=1; }
exit $fail
