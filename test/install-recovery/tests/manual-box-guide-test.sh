#!/usr/bin/env bash
# The manual box tests the newest release candidate. The guide's setup,
# install and uninstall commands use statbus.org/rc/ (STATBUS-570), which runs
# that candidate's own scripts; the guide names the candidate they resolve to.
# Double: gh lists the newest prerelease; no server is needed for the guide.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/manual-box-guide.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
echo 'HCLOUD_TOKEN=test-token-not-a-secret' > "$work/creds"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Like gh: release list --json ... -q <jq> applies the jq filter to the list.
[ "$1 $2" = "release list" ] || { echo "gh double: unexpected $*" >&2; exit 64; }
filter=""
while [ $# -gt 0 ]; do case "$1" in -q) filter=$2; shift 2 ;; *) shift ;; esac; done
printf '%s' '[{"tagName":"v2026.12.0","isPrerelease":false},{"tagName":"v2026.11.1-rc.06","isPrerelease":true},{"tagName":"v2026.11.1-rc.05","isPrerelease":true}]' \
    | jq -r "$filter"
EOF
chmod +x "$work/bin/gh"

out="$(PATH="$work/bin:$PATH" STATBUS_CREDENTIALS_FILE="$work/creds" bash "$ROOT/ops/manual-box.sh" guide 2>&1)"
fail=0
for want in \
    "Release:           v2026.11.1-rc.06 (the newest candidate; statbus.org/rc/ runs it)" \
    "curl -fsSL https://statbus.org/rc/setup.sh | bash" \
    "curl -fsSL https://statbus.org/rc/install.sh | bash" \
    "curl -fsSL https://statbus.org/rc/uninstall.sh | bash"; do
    if grep -Fq -- "$want" <<<"$out"; then
        echo "PASS guide shows: $want"
    else
        echo "FAIL guide shows: $want"
        fail=1
    fi
done
if [ "$fail" = 0 ]; then
    echo "manual-box guide test: PASS"
else
    printf '%s\n' "$out" | sed 's/^/    /'
    echo "manual-box guide test: FAIL"
    exit 1
fi
