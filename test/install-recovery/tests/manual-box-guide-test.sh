#!/usr/bin/env bash
# The manual box tests the newest release, usually a candidate. The guide's
# setup, install and uninstall commands fetch that release's own scripts and
# install that release; statbus.org's shortcuts serve the latest stable.
# Doubles: gh lists the newest release; no server is needed for the guide.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/manual-box-guide.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
echo 'HCLOUD_TOKEN=test-token-not-a-secret' > "$work/creds"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "release list" ] || { echo "gh double: unexpected $*" >&2; exit 64; }
echo v2026.11.1-rc.06
EOF
chmod +x "$work/bin/gh"

out="$(PATH="$work/bin:$PATH" STATBUS_CREDENTIALS_FILE="$work/creds" bash "$ROOT/ops/manual-box.sh" guide 2>&1)"
base=https://github.com/statisticsnorway/statbus/releases/download/v2026.11.1-rc.06
fail=0
for want in \
    "Release:           v2026.11.1-rc.06" \
    "curl -fsSL $base/setup-ubuntu-lts.sh -o setup.sh && bash setup.sh" \
    "curl -fsSL $base/install.sh | bash -s -- --version v2026.11.1-rc.06" \
    "curl -fsSL $base/uninstall.sh | bash"; do
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
