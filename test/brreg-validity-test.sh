#!/bin/bash
# Transport contract only: no database or remote host is contacted.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/samples/norway" "$TMP/tmp" "$TMP/bin"
git -C "$TMP" init -q
cp -R "$ROOT/samples/norway/brreg" "$TMP/samples/norway/"
cp "$ROOT/samples/norway/getting-started.sql" "$TMP/samples/norway/"
cp "$ROOT/cloud.sh" "$TMP/"
: >"$TMP/tmp/roller_legal_relationships.csv"
mkdir -p "$TMP/remote"
ln -s "$TMP" "$TMP/remote/statbus"
export REMOTE="$TMP/remote"
export CAPTURE="$TMP/capture"
cat >"$TMP/sb" <<'STUB'
#!/bin/bash
[ -z "${EXPECT_DATABASE:-}" ] || { [ "$1" = psql ] && [ "$2" = -d ] && [ "$3" = "$EXPECT_DATABASE" ]; } || exit 90
[ -z "${EXPECT_EMAIL:-}" ] || [ "$USER_EMAIL" = "$EXPECT_EMAIL" ] || exit 91
printf '%s\n' "$@" >>"$CAPTURE"
if [[ "${!#}" = *'BRREG explicit validity preflight'* ]]; then
    printf 'READ_PREFLIGHT\n' >>"$CAPTURE.events"
    if [ "${PREFLIGHT_ERROR:-0}" = 1 ]; then exit 92; fi
    printf '%s' "${EXISTING_MISMATCH:-}"
    exit 0
fi
input=$(cat)
if [[ "${!#}" = *'INSERT INTO public.import_job'* || "${!#}" = *'\copy '* ]] || [ -n "$input" ]; then
    printf 'WRITE\n' >>"$CAPTURE.events"
else
    printf 'READ\n' >>"$CAPTURE.events"
fi
echo user-id
STUB
cat >"$TMP/bin/ssh" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >>"$CAPTURE"
if [ "${EXEC_SSH:-0}" = 1 ]; then cd "$REMOTE"; bash -c "${!#}"; fi
STUB
chmod +x "$TMP/sb" "$TMP/bin/ssh"
export PATH="$TMP/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
run_loader() { : >"$CAPTURE"; : >"$CAPTURE.events"; USER_EMAIL=test@example.com bash "$TMP/samples/norway/brreg/brreg-import-$1.sh" "${@:2}" >"$TMP/output" 2>&1; }
assert_job_dates() {
    local actual
    actual=$(awk '/SELECT def.id,/ { getline; getline; gsub(/^[[:space:]]+/, ""); print }' "$CAPTURE")
    [ "$actual" = "$(printf "'%s'::DATE,\n'%s'::DATE,\n'%s'::DATE," "$1" "$1" "$1")" ] || fail "all three job dates: $actual"
}
for loader in selection downloads-from-tmp; do
    for validity in '--valid-from 2024-02-29' '--year 2024'; do
        # Both explicit interfaces must refuse a conflict before any setup write.
        # shellcheck disable=SC2086
        if EXISTING_MISMATCH='import_roller conflict' run_loader "$loader" $validity; then fail "$loader accepted existing date mismatch"; fi
        [ "$(cat "$CAPTURE.events")" = READ_PREFLIGHT ] || fail "$loader conflict must stop at read-only preflight"
        grep -q 'existing.*validity' "$TMP/output" || fail 'actionable conflict error'
        for unit in hovedenhet underenhet roller; do
            slug=import_${unit}_2025
            [ "$loader" != selection ] || slug=import_${unit}_2024_selection
            grep -q "'$slug'" "$CAPTURE" || fail "preflight includes $slug"
        done
    done
    if PREFLIGHT_ERROR=1 run_loader "$loader" --year 2024; then fail 'preflight query failure accepted'; fi
    [ "$(cat "$CAPTURE.events")" = READ_PREFLIGHT ] || fail 'query failure must stop before writes'
    EXPECT_DATABASE=fixture run_loader "$loader" --year 2024 --database fixture
    [ "$(head -1 "$CAPTURE.events")" = READ_PREFLIGHT ] || fail 'preflight must precede all setup operations'
    grep -q '^WRITE$' "$CAPTURE.events" || fail 'matching/absent dates must continue to setup'
    EXISTING_MISMATCH='legacy conflicting date' run_loader "$loader"
    [ "$(head -1 "$CAPTURE.events")" = READ ] || fail 'legacy invocation must keep original read-first behavior'
    grep -q '^WRITE$' "$CAPTURE.events" || fail 'legacy invocation must proceed unchanged'
    run_loader "$loader" --valid-from 2024-02-29
    assert_job_dates 2024-02-29
    EXPECT_DATABASE=fixture run_loader "$loader" --valid-from 2024-02-29 --database fixture
    assert_job_dates 2024-02-29
    grep -q '^fixture$' "$CAPTURE" || fail 'database propagation'
    if [ "$loader" = selection ]; then grep -q import_roller_2024_selection "$CAPTURE" || fail 'date year slug'; fi
    EXPECT_DATABASE=fixture run_loader "$loader" --database fixture --year 2020
    assert_job_dates 2020-01-01
    EXPECT_DATABASE='fixture db' run_loader "$loader" --database 'fixture db' --year 2020
    assert_job_dates 2020-01-01
    run_loader "$loader" --valid-from 2000-02-29
    assert_job_dates 2000-02-29
    run_loader "$loader"
    expected=$(date +%Y)-01-01
    [ "$loader" = selection ] || expected=$(date +%Y-%m-%d)
    assert_job_dates "$expected"
    for args in '--valid-from 2023-02-29' '--valid-from 1900-02-29' '--valid-from 2024-04-31' '--valid-from 2024-00-01' '--valid-from 2024-13-01' '--valid-from 2024-01-00' '--valid-from 2024-2-29' '--valid-from 0000-01-01' '--year 20' '--year' '--database' '--unknown' '--year 2024 --year 2024' '--valid-from 2024-01-01 --year 2024' '--database a --database b' '--help --help' '--year --database fixture' '--valid-from 2024-01-01;touch'; do
        # Intentional word splitting supplies malformed command-line fixtures.
        # shellcheck disable=SC2086
        if run_loader "$loader" $args; then fail "$loader accepted $args"; fi
        [ ! -s "$CAPTURE" ] || fail "$loader refusal contacted sb: $args"
    done
    : >"$CAPTURE"
    env -u USER_EMAIL bash "$TMP/samples/norway/brreg/brreg-import-$loader.sh" --help >"$TMP/output"
    [ ! -s "$CAPTURE" ] || fail 'help contacted sb'
done
run_cloud() { : >"$CAPTURE"; : >"$CAPTURE.events"; bash "$TMP/cloud.sh" import "$@" >"$TMP/output" 2>&1; }
for variant in selection downloads; do
    if EXEC_SSH=1 EXISTING_MISMATCH='existing validity conflict' run_cloud no "$variant" test@example.com --year 2024; then fail 'cloud accepted explicit conflict'; fi
    [ "$(cat "$CAPTURE.events")" = READ_PREFLIGHT ] || fail 'cloud conflict must stop before setup writes'
done
EXEC_SSH=1 EXPECT_DATABASE=fixture EXPECT_EMAIL=test@example.com STATBUS_REIMPORT_USER_EMAIL=ignored@example.com run_cloud no selection test@example.com --valid-from 2024-02-29 --database fixture
assert_job_dates 2024-02-29
# The SSH shell must preserve email as data, not execute its metacharacters.
# shellcheck disable=SC2016 # Literal shell syntax is the email roundtrip fixture.
email='operator+$(false)@example.com'
EXEC_SSH=1 EXPECT_EMAIL="$email" run_cloud no downloads "$email" --year 2020
assert_job_dates 2020-01-01
EXEC_SSH=1 EXPECT_DATABASE='fixture db' EXPECT_EMAIL=test@example.com run_cloud no downloads test@example.com --database 'fixture db' --year 2020
assert_job_dates 2020-01-01
run_cloud no selection test@example.com --valid-from 2024-02-29 --database fixture
grep -q -- '--valid-from 2024-02-29 --database fixture' "$CAPTURE" || fail 'cloud date/database forwarding'
STATBUS_REIMPORT_USER_EMAIL=env@example.com run_cloud all downloads --year 2020
grep -q -- '--year 2020' "$CAPTURE" || fail 'cloud year forwarding'
grep -q 'env@example.com' "$CAPTURE" || fail 'cloud env email'
[ "$(grep -c '@' "$CAPTURE")" -eq 2 ] || fail 'all standalone grouping'
for target in no prerelease; do
    for args in '--year 2024 --year 2024' '--valid-from 2023-02-29' '--valid-from 2024-01-01 --year 2024' '--database' '--unknown' '--valid-from 2024-01-01;false'; do
        # Intentional splitting supplies malformed CLI fixtures.
        # shellcheck disable=SC2086
        if run_cloud "$target" selection test@example.com $args; then fail "cloud accepted $args"; fi
        [ ! -s "$CAPTURE" ] || fail 'cloud refusal contacted SSH'
    done
done
if run_cloud prerelease unknown test@example.com --year 2024; then fail 'unknown variant accepted'; fi
[ ! -s "$CAPTURE" ] || fail 'unknown variant contacted SSH'
run_cloud --help
[ ! -s "$CAPTURE" ] || fail 'cloud bare help contacted SSH'
run_cloud no selection --help
[ ! -s "$CAPTURE" ] || fail 'cloud help contacted SSH'
echo 'BRREG validity transport contracts passed'
