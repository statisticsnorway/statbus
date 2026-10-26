#!/usr/bin/env bash
# STATBUS-529 AC1 regression: dev.sh postgres-variables must export PGHOST
# from CADDY_DB_BIND_ADDRESS (where the database route actually binds), never
# from SITE_DOMAIN — a public site name may not even resolve on this host.
# Reproduced 2026-10-26 with SITE_DOMAIN=test.statbus.org unresolvable on a
# Mac while .env correctly carried CADDY_DB_BIND_ADDRESS=127.0.0.1.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH_ROOT=${JCODE_SCRATCH_DIR:-$REPO_ROOT/tmp}
mkdir -p "$SCRATCH_ROOT"

fixture=$(mktemp -d "$SCRATCH_ROOT/dev-postgres-variables.XXXXXX")
git clone --quiet --no-hardlinks "$REPO_ROOT" "$fixture/repo"
# DEV_SH_SOURCE override lets a RED run point at a pre-fix dev.sh (e.g.
# `git show HEAD~1:dev.sh`) without disturbing the shared checkout.
cp "${DEV_SH_SOURCE:-$REPO_ROOT/dev.sh}" "$fixture/repo/dev.sh"

cat >"$fixture/repo/.env" <<'EOF'
SITE_DOMAIN=unresolvable.statbus.invalid
CADDY_DB_BIND_ADDRESS=127.0.0.1
CADDY_DB_PORT=3034
CADDY_DB_TLS_PORT=3035
POSTGRES_APP_DB=statbus
POSTGRES_ADMIN_USER=postgres
POSTGRES_ADMIN_PASSWORD=secret
EOF

# Stub sb: fresh for the preamble drift checks, answers dotenv lookups from
# the fixture .env.
cat >"$fixture/repo/sb" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  committed-drift) exit 0 ;;
  dotenv)
    key="${5:-}"
    value=$(grep -E "^${key}=" .env | tail -1 | cut -d= -f2- || true)
    if [ -z "$value" ]; then exit 1; fi
    printf '%s\n' "$value"
    ;;
esac
exit 0
EOF
chmod +x "$fixture/repo/sb"
# Beat the mtime hot-edit axis: sb newer than any cli/**/*.go from the clone.
touch -t 203001010000 "$fixture/repo/sb"

output=$(cd "$fixture/repo" && ./dev.sh postgres-variables)
printf '%s\n' "$output" | grep -q "PGHOST=127.0.0.1" || {
    echo "FAIL: plain mode did not export PGHOST=127.0.0.1" >&2
    echo "$output" >&2
    exit 1
}
if printf '%s\n' "$output" | grep -q "unresolvable.statbus.invalid"; then
    echo "FAIL: PGHOST came from SITE_DOMAIN" >&2
    echo "$output" >&2
    exit 1
fi
echo "PASS: plain mode exports PGHOST=127.0.0.1 (bind address), ignoring unresolvable SITE_DOMAIN"

tls_output=$(cd "$fixture/repo" && TLS=1 ./dev.sh postgres-variables)
printf '%s\n' "$tls_output" | grep -q "PGHOST=127.0.0.1" || {
    echo "FAIL: TLS mode did not export PGHOST=127.0.0.1" >&2
    echo "$tls_output" >&2
    exit 1
}
printf '%s\n' "$tls_output" | grep -q "PGPORT=3035" || {
    echo "FAIL: TLS mode did not export PGPORT from CADDY_DB_TLS_PORT" >&2
    echo "$tls_output" >&2
    exit 1
}
echo "PASS: TLS mode exports PGHOST=127.0.0.1 with PGPORT=3035"
