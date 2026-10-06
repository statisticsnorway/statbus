#!/usr/bin/env bash
# Offline execution of extracted, unchanged source bodies. Not full entrypoint proof.
set -euo pipefail
source_file=${1:?dev.sh source required}
evidence=${2:?retained evidence directory required}
mkdir -p "$evidence/test/expected" "$evidence/test/results"
source_file=$(cd "$(dirname "$source_file")" && pwd)/$(basename "$source_file")
WORKSPACE=$(cd "$evidence" && pwd)
PG_REGRESS_DIR="$WORKSPACE/test"
PG_REGRESS=fixture-pg-regress
POSTGRESQL_MAJOR=18
CONTAINER_REGRESS_DIR=/statbus/test
SHARED_TEST_DB=fixture_shared
TEST_DB=fixture_isolated
PGUSER=fixture
debug_arg=''
SHARED_TESTS=shared
TEST_NAME=isolated
export WORKSPACE PG_REGRESS_DIR PG_REGRESS POSTGRESQL_MAJOR CONTAINER_REGRESS_DIR SHARED_TEST_DB TEST_DB PGUSER debug_arg SHARED_TESTS TEST_NAME
# Only these exact producer arguments may reach this refusing shell double.
docker() {
    [[ "$*" == "compose exec --workdir /statbus db fixture-pg-regress --use-existing --bindir=/usr/lib/postgresql/18/bin --inputdir=/statbus/test --outputdir=/statbus/test --dbname=fixture_"* ]] || return 97
    printf '%s\n' "$record"
    return "$producer_status"
}
export -f docker
awk '/^[ ]*docker compose exec --workdir "\/statbus" db \\/ { body=$0 ORS; active=1; next } active { body=body $0 ORS; if (/EXIT_CODE=\$\?/) { print body; active=0 } }' "$source_file" > "$WORKSPACE/producers.sh"
# There are exactly two pg_regress commands at these source boundaries.
[[ $(grep -c 'EXIT_CODE=\$?' "$WORKSPACE/producers.sh") -eq 2 ]]
awk '/OVERALL_EXIT_CODE=\$\?/ { print; exit } {print}' "$WORKSPACE/producers.sh" > "$WORKSPACE/shared.sh"
awk 'seen {print} /OVERALL_EXIT_CODE=\$\?/ {seen=1}' "$WORKSPACE/producers.sh" > "$WORKSPACE/isolated.sh"
run_producer() {
    local body=$1 status=$2 text=$3
    producer_status=$status record=$text
    export producer_status record
    bash -c 'set -euo pipefail; OVERALL_EXIT_CODE=0; TEST_EXIT_CODE=0; source "$1"; exit "$((OVERALL_EXIT_CODE | TEST_EXIT_CODE))"' bash "$WORKSPACE/$body.sh"
}
set +e
run_producer shared 7 'not ok 1 - shared' > "$WORKSPACE/shared.console"
shared_exit=$?
run_producer isolated 0 'ok 1 - isolated' > "$WORKSPACE/isolated.console"
isolated_exit=$?
set -e
printf 'shared_exit=%s isolated_exit=%s summary_exists=%s\n' "$shared_exit" "$isolated_exit" "$([[ -f "$PG_REGRESS_DIR/regression.out" ]] && echo yes || echo no)"
[[ $shared_exit -eq 7 && $isolated_exit -eq 0 ]]
printf 'not ok 1 - shared\n' | cmp - "$WORKSPACE/shared.console"
printf 'ok 1 - isolated\n' | cmp - "$WORKSPACE/isolated.console"
if [[ -f "$PG_REGRESS_DIR/regression.out" ]]; then
    printf 'not ok 1 - shared\nok 1 - isolated\n' | cmp - "$PG_REGRESS_DIR/regression.out"
fi
# Extract the complete case arm, with no bootstrap or DB calls.
awk "/^    'diff-fail-all' \)/ {active=1; next} active && /^    ;;/ {exit} active {print}" "$source_file" > "$WORKSPACE/reader.sh"
printf 'ok 1 - isolated\n' > "$PG_REGRESS_DIR/regression.out"
set +e
bash -euo pipefail "$WORKSPACE/reader.sh" pipe > "$WORKSPACE/reader.console" 2>&1
reader_exit=$?
set -e
printf 'no_match_reader_exit=%s\n' "$reader_exit"
[[ $reader_exit -eq 0 ]]
grep -q 'No failing tests found' "$WORKSPACE/reader.console"

# Execute the exact lifecycle blocks, without executing selection/preconditions.
awk '/# Start one current-run inventory/ {active=1; next} active {print; exit}' "$source_file" > "$WORKSPACE/fresh.sh"
awk '/# Children retain the parent/ {active=1; next} active {print; if (/^[ ]*fi$/) exit}' "$source_file" > "$WORKSPACE/child-init.sh"
[[ -s "$WORKSPACE/fresh.sh" && -s "$WORKSPACE/child-init.sh" ]]
printf 'old run\n' > "$PG_REGRESS_DIR/regression.out"
bash -euo pipefail "$WORKSPACE/fresh.sh"
[[ ! -s "$PG_REGRESS_DIR/regression.out" ]]
set +e
run_producer shared 7 'not ok 1 - shared' > "$WORKSPACE/shared-again.console"
status=$?
set -e
[[ $status -eq 7 ]]
STATBUS_REGRESSION_APPEND=1 bash -euo pipefail "$WORKSPACE/child-init.sh"
run_producer isolated 0 'ok 1 - isolated' > "$WORKSPACE/child-pass.console"
set +e
run_producer isolated 9 'not ok 1 - isolated' > "$WORKSPACE/child-fail.console"
status=$?
set -e
[[ $status -eq 9 ]]
STATBUS_REGRESSION_APPEND=1 bash -euo pipefail "$WORKSPACE/child-init.sh"
run_producer isolated 0 'ok 1 - isolated' > "$WORKSPACE/child-pass2.console"
printf 'not ok 1 - shared\nok 1 - isolated\nnot ok 1 - isolated\nok 1 - isolated\n' | cmp - "$PG_REGRESS_DIR/regression.out"
cp "$PG_REGRESS_DIR/regression.out" "$WORKSPACE/combined-retained.out"
printf 'expected shared\n' > "$PG_REGRESS_DIR/expected/shared.out"
printf 'actual shared\n' > "$PG_REGRESS_DIR/results/shared.out"
printf 'expected isolated\n' > "$PG_REGRESS_DIR/expected/isolated.out"
printf 'actual isolated\n' > "$PG_REGRESS_DIR/results/isolated.out"
bash -euo pipefail "$WORKSPACE/reader.sh" pipe > "$WORKSPACE/failure-diffs.console"
grep -q 'expected shared' "$WORKSPACE/failure-diffs.console"
grep -q 'actual isolated' "$WORKSPACE/failure-diffs.console"
STATBUS_REGRESSION_APPEND=0 bash -euo pipefail "$WORKSPACE/child-init.sh"
[[ ! -s "$PG_REGRESS_DIR/regression.out" ]]
set +e
run_producer isolated 9 'not ok 1 - isolated' > "$WORKSPACE/standalone.console"
status=$?
set -e
[[ $status -eq 9 ]]
printf 'not ok 1 - isolated\n' | cmp - "$PG_REGRESS_DIR/regression.out"
# Execute the checked-in parent loop and its scoped environment assignment.
awk '/^        if \[ -n "\$ISOLATED_TESTS" \]/ {active=1} active && /# STATBUS-278 Part 2/ {exit} active {print}' "$source_file" > "$WORKSPACE/parent-loop.sh"
cat > "$WORKSPACE/dev.sh" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == test-isolated && ${STATBUS_REGRESSION_APPEND:-0} == 1 ]] || exit 96
TEST_NAME=$2
source "$WORKSPACE/child-init.sh"
record="ok 1 - $TEST_NAME" producer_status=0
if [[ $TEST_NAME == isolated_fail ]]; then
    record="not ok 1 - $TEST_NAME" producer_status=9
fi
TEST_EXIT_CODE=0
source "$WORKSPACE/isolated.sh"
exit "$TEST_EXIT_CODE"
CHILD
chmod +x "$WORKSPACE/dev.sh"
bash -euo pipefail "$WORKSPACE/fresh.sh"
set +e
(cd "$WORKSPACE" && bash -euo pipefail -c 'ISOLATED_TESTS="isolated_fail isolated_pass"; update_expected=false; OVERALL_EXIT_CODE=0; source "$WORKSPACE/parent-loop.sh"; exit "$OVERALL_EXIT_CODE"') > "$WORKSPACE/parent-loop.console" 2>&1
parent_exit=$?
set -e
[[ $parent_exit -eq 9 ]]
printf 'not ok 1 - isolated_fail\nok 1 - isolated_pass\n' | cmp - "$PG_REGRESS_DIR/regression.out"
cp "$PG_REGRESS_DIR/regression.out" "$WORKSPACE/wired-children-retained.out"
printf 'actual_parent_loop_exit=%s\n' "$parent_exit"
# Keep all evidence. A directory at the capture path deterministically refuses tee.
mv "$PG_REGRESS_DIR/regression.out" "$WORKSPACE/standalone-retained.out"
mkdir "$PG_REGRESS_DIR/regression.out"
set +e
run_producer shared 0 'ok 1 - shared' > "$WORKSPACE/write-failure.console" 2> "$WORKSPACE/write-failure.stderr"
write_exit=$?
run_producer isolated 0 'ok 1 - isolated' > "$WORKSPACE/isolated-write-failure.console" 2> "$WORKSPACE/isolated-write-failure.stderr"
isolated_write_exit=$?
bash -euo pipefail "$WORKSPACE/reader.sh" pipe > "$WORKSPACE/missing.console" 2>&1
missing_exit=$?
set -e
[[ $write_exit -eq 1 && $isolated_write_exit -eq 1 && $missing_exit -eq 1 ]]
grep -q 'Inspect the SQL step output' "$WORKSPACE/missing.console"
printf 'ok 1 - shared\n' | cmp - "$WORKSPACE/write-failure.console"
mv "$PG_REGRESS_DIR/regression.out" "$WORKSPACE/capture-directory"
printf 'ok 1 - isolated\n' > "$PG_REGRESS_DIR/regression.out"
awk "/^    'diff-fail-first' \)/ {active=1; next} active && /^    ;;/ {exit} active {print}" "$source_file" > "$WORKSPACE/first-reader.sh"
bash -euo pipefail "$WORKSPACE/first-reader.sh" pipe > "$WORKSPACE/first-reader.console"
grep -q 'No failing tests found' "$WORKSPACE/first-reader.console"
# Inject grep status 2 after the precheck to verify real read errors are not masked.
set +e
bash -euo pipefail -c 'grep() { return 2; }; source "$1"' bash "$WORKSPACE/reader.sh" > "$WORKSPACE/read-error.console" 2>&1
read_exit=$?
set -e
[[ $read_exit -eq 2 ]]
printf 'multiple_children=retained standalone=fresh isolated_exit=9 write_exit=%s missing_exit=%s read_error_exit=%s first_reader_exit=0\n' "$write_exit" "$missing_exit" "$read_exit"
