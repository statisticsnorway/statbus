#!/usr/bin/env bash
# STATBUS-529 AC2 regression: delete-seed's existence check has three
# outcomes — present, absent, unreachable — not two. A failed psql query
# must exit non-zero with the connection error and must never print
# "nothing to delete" (the 2026-10-26 incident: the following create then
# collided with the database that was actually still there). A successful
# empty result still means genuinely absent and remains a no-op.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH_ROOT=${JCODE_SCRATCH_DIR:-$REPO_ROOT/tmp}
mkdir -p "$SCRATCH_ROOT"

fixture=$(mktemp -d "$SCRATCH_ROOT/dev-delete-seed.XXXXXX")
git clone --quiet --no-hardlinks "$REPO_ROOT" "$fixture/repo"
# DEV_SH_SOURCE override lets a RED run point at a pre-fix dev.sh (e.g.
# `git show HEAD~1:dev.sh`) without disturbing the shared checkout.
cp "${DEV_SH_SOURCE:-$REPO_ROOT/dev.sh}" "$fixture/repo/dev.sh"
mkdir -p "$fixture/repo/tmp"

cat >"$fixture/repo/.env" <<'EOF'
CADDY_DB_BIND_ADDRESS=127.0.0.1
CADDY_DB_PORT=3034
POSTGRES_APP_DB=statbus
POSTGRES_ADMIN_USER=postgres
POSTGRES_ADMIN_PASSWORD=secret
EOF

# Stub sb: fresh for the preamble drift checks, answers dotenv lookups, and
# simulates psql per SB_PSQL_MODE (fail = connection error, absent = empty
# success). STATBUS_TEST_LOCK_HELD=1 below isolates the unit under test from
# the shared-state lock's docker/psql environment probes.
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
  psql)
    if [ "${SB_PSQL_MODE:-absent}" = "fail" ]; then
      echo 'psql: error: connection to server at "127.0.0.1", port 3034 failed: Connection refused' >&2
      exit 1
    fi
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$fixture/repo/sb"
touch -t 203001010000 "$fixture/repo/sb"

# Case 1: existence query fails → non-zero exit, the connection error is
# visible, and nothing claims the seed is absent.
set +e
fail_output=$(cd "$fixture/repo" && SB_PSQL_MODE=fail STATBUS_TEST_LOCK_HELD=1 ./dev.sh delete-seed 2>&1)
fail_rc=$?
set -e
if [ "$fail_rc" -eq 0 ]; then
    echo "FAIL: delete-seed exited 0 although the existence query failed" >&2
    echo "$fail_output" >&2
    exit 1
fi
printf '%s\n' "$fail_output" | grep -q "Connection refused" || {
    echo "FAIL: connection error was swallowed" >&2
    echo "$fail_output" >&2
    exit 1
}
if printf '%s\n' "$fail_output" | grep -q "nothing to delete"; then
    echo "FAIL: delete-seed claimed the seed was absent after a failed query" >&2
    echo "$fail_output" >&2
    exit 1
fi
echo "PASS: failed existence query exits $fail_rc with the connection error and never claims absent"

# Case 2: existence query succeeds with an empty result → the seed is
# genuinely absent and delete-seed is a successful no-op.
absent_output=$(cd "$fixture/repo" && SB_PSQL_MODE=absent STATBUS_TEST_LOCK_HELD=1 ./dev.sh delete-seed 2>&1)
printf '%s\n' "$absent_output" | grep -q "does not exist; nothing to delete." || {
    echo "FAIL: genuinely absent seed was not reported as a no-op" >&2
    echo "$absent_output" >&2
    exit 1
}
echo "PASS: genuinely absent seed is a successful no-op"
