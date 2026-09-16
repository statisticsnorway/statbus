#!/bin/bash
# Offline contract test for dev.sh's seed fast-path fallback helper.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-dev-seed.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/work/.db-seed" "$TMP_ROOT/work/bin"
cp "$ROOT/ops/dev-seed-restore.sh" "$TMP_ROOT/work/helper.sh"
cat > "$TMP_ROOT/work/sb" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$TRACE"
exit "${RESTORE_RC:-0}"
MOCK
chmod +x "$TMP_ROOT/work/sb"

create_branch=$(sed -n "/'create-db-structure' )/,/;;/p" "$ROOT/dev.sh")
restore_line=$(printf '%s\n' "$create_branch" | grep -n 'restore_dev_seed_or_fallback' | cut -d: -f1)
migrate_line=$(printf '%s\n' "$create_branch" | grep -n './sb migrate up' | cut -d: -f1)
[ -n "$restore_line" ] && [ -n "$migrate_line" ] && [ "$restore_line" -lt "$migrate_line" ]
if printf '%s\n' "$create_branch" | grep -q 'Seed restore failed.*exit 1'; then
    echo 'FAIL: create-db-structure still aborts after a seed restore failure'
    exit 1
fi

run_case() {
    local rc=$1
    local output=$2
    : > "$TMP_ROOT/trace"
    printf dump > "$TMP_ROOT/work/.db-seed/seed.pg_dump"
    printf '{}\n' > "$TMP_ROOT/work/.db-seed/seed.json"
    (
        cd "$TMP_ROOT/work"
        export TRACE="$TMP_ROOT/trace" RESTORE_RC="$rc"
        source ./helper.sh
        restore_dev_seed_or_fallback "$TMP_ROOT/work"
    ) > "$output" 2>&1
    grep -Fxq 'db seed restore' "$TMP_ROOT/trace"
}

run_case 22 "$TMP_ROOT/incompatible.out"
grep -q 'incompatible with this checkout' "$TMP_ROOT/incompatible.out"
grep -q 'Falling back to full migrations' "$TMP_ROOT/incompatible.out"
[ ! -e "$TMP_ROOT/work/.db-seed/seed.pg_dump" ]
[ ! -e "$TMP_ROOT/work/.db-seed/seed.json" ]
echo 'PASS: incompatible cache is deleted and full replay remains available'

run_case 1 "$TMP_ROOT/restore-failure.out"
grep -q 'Seed restore failed (exit 1); falling back to full migrations' "$TMP_ROOT/restore-failure.out"
[ -e "$TMP_ROOT/work/.db-seed/seed.pg_dump" ]
[ -e "$TMP_ROOT/work/.db-seed/seed.json" ]
echo 'PASS: genuine restore failure is loud, non-fatal, and does not masquerade as incompatibility'

RESTORE_RC=0 run_case 0 "$TMP_ROOT/success.out"
[ -e "$TMP_ROOT/work/.db-seed/seed.pg_dump" ]
echo 'PASS: successful restore preserves the cache'

rm -f "$TMP_ROOT/work/.db-seed/seed.pg_dump" "$TMP_ROOT/work/.db-seed/seed.json"
(
    cd "$TMP_ROOT/work"
    source ./helper.sh
    restore_dev_seed_or_fallback "$TMP_ROOT/work"
) > "$TMP_ROOT/missing.out"
grep -q 'No seed found' "$TMP_ROOT/missing.out"
echo 'dev-seed-restore tests: PASS'
