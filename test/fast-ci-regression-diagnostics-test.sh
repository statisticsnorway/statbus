#!/usr/bin/env bash
# Execute the unchanged workflow diagnostic body with a refusing Docker double.
# Real local tar/diff recover a prior shared failure after a passing child.
# No daemon, database, network, or dev.sh bootstrap is invoked.
set -euo pipefail
workflow=${1:-.github/workflows/fast-tests.yaml}
evidence=${2:?usage: bash test/fast-ci-regression-diagnostics-test.sh workflow retained-evidence-dir}
workflow=$(cd "$(dirname "$workflow")" && pwd)/$(basename "$workflow")
mkdir -p "$evidence"
evidence=$(cd "$evidence" && pwd)
evidence=$(mktemp -d "$evidence/run.XXXXXX")
printf 'Evidence: %s\n' "$evidence"
mkdir -p "$evidence/bin" "$evidence/container/results/nested" "$evidence/expected"
awk '
  /^      - name: Show regression diffs on failure$/ { step=1; next }
  step && /^        run: \|$/ { body=1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$workflow" > "$evidence/diffs.sh"
awk '
  /^      - name: Capture PostgreSQL plans$/ { step=1; next }
  step && /^        run: \|$/ { body=1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$workflow" > "$evidence/plans.sh"
for body in diffs plans; do
  test -s "$evidence/$body.sh"
  bash -n "$evidence/$body.sh"
done
shared=374_statbus_591_power_group_processing_scales_with_relationships.out
isolated=094_read_only_window_worker_recovery_exemption.out
printf 'expected shared output\n' > "$evidence/expected/$shared"
printf 'actual earlier shared mismatch\n' > "$evidence/container/results/$shared"
printf 'passing isolated output\n' > "$evidence/expected/$isolated"
cp "$evidence/expected/$isolated" "$evidence/container/results/$isolated"
printf 'auxiliary\000result bytes\377\n' > "$evidence/container/results/nested/opaque.bin"
printf 'ok 1 - 094_read_only_window_worker_recovery_exemption\n1..1\n' > "$evidence/container/regression.out"
printf 'last invocation raw diagnostic\n' > "$evidence/container/regression.diffs"
printf '%s\n' 'db | LOG: duration: 1729 ms plan:' 'db | Query Text: SELECT fixture FROM fixture_rows WHERE id = fixture_id' 'db | Nested Loop (actual rows=6000 loops=1)' > "$evidence/container/postgres.log"
cat > "$evidence/mock-sb" <<'SB'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'dotenv -f .env parse' || "$*" == 'dotenv -f .env.credentials parse' ]] || exit 97
if [[ $MODE == config-error ]]; then echo 'fixture config read failed with fixture-jwt-secret' >&2; exit 49; fi
if [[ $MODE == config-incomplete ]]; then echo 'OTHER=fixture'; exit 0; fi
printf '%s\n' 'POSTGRES_ADMIN_PASSWORD=fixture-password' 'JWT_SECRET=fixture-jwt-secret' "APP_PASSWORD=fixture'quoted-password"
SB
chmod +x "$evidence/mock-sb"
# Model the container's root-owned mode-600 files, using a real tar archive.
python3 - "$evidence/container" <<'PY'
import pathlib
import sys
import tarfile
root = pathlib.Path(sys.argv[1])
def container_owner(member):
    member.uid = member.gid = 0
    member.uname = member.gname = "root"
    member.mode = 0o700 if member.isdir() else 0o600
    return member
with tarfile.open(root / "results.tar", "w") as archive:
    archive.add(root / "results", arcname="results", filter=container_owner)
PY
mkdir -p "$evidence/empty/results"
printf 'no completed tests\n' > "$evidence/empty/results/incomplete.txt"
tar -cf "$evidence/container/empty.tar" -C "$evidence/empty" results
cat > "$evidence/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == 'compose logs --no-color db' ]]; then
  printf '%s\n' "$*" >> "$CALLS"
  if [[ $MODE == unavailable ]]; then echo 'fixture: db unavailable' >&2; exit 42; fi
  if [[ $MODE == privacy ]]; then
    printf '%s\n' "db | SQL literal: fixture-jwt-secret fixture''quoted-password eyJmb28iOiJiYXIifQ.eyJzdWIiOiJmaXh0dXJlIn0.c2lnbmF0dXJl"
    printf '%s\n' 'fixture stderr: fixture-password' >&2
  else
    cat "$CONTAINER/postgres.log"
  fi
  if [[ $MODE == log-failure || $MODE == success-log-failure ]]; then echo 'fixture: log transport failed' >&2; exit 71; fi
  exit 0
fi
[[ $# -ge 8 && "$1 $2 $3 $4 $5 $6" == 'compose exec -T --workdir /statbus db' ]] || exit 97
shift 6
printf '%s\n' "$*" >> "$CALLS"
if [[ $MODE == unavailable ]]; then echo 'fixture: db unavailable' >&2; exit 42; fi
case "$*" in
  'cat /statbus/test/regression.out'|'cat /statbus/test/regression.diffs')
    file=${2##*/}
    case "$MODE:$file" in
      recovery:regression.out) echo 'fixture: summary missing after passing isolated child' >&2; exit 1 ;;
      missing-summary:regression.out) echo 'fixture: summary missing' >&2; exit 1 ;;
      recovery:regression.diffs|missing-diff:regression.diffs) echo 'fixture: diff missing after passing isolated child' >&2; exit 1 ;;
      partial:regression.diffs) printf 'partial diff bytes\n'; echo 'fixture: stream interrupted' >&2; exit 43 ;;
    esac
    cat "$CONTAINER/$file" ;;
  'tar -cf - -C /statbus/test results')
    case "$MODE" in
      archive-error) echo 'fixture: archive collection failed' >&2; exit 44 ;;
      archive-partial) cat "$CONTAINER/results.tar"; echo 'fixture: archive stream failed' >&2; exit 45 ;;
      corrupt-archive) printf 'not a tar archive\n' ;;
      empty-results) cat "$CONTAINER/empty.tar" ;;
      *) cat "$CONTAINER/results.tar" ;;
    esac ;;
  *) echo "refused docker: $*" >&2; exit 97 ;;
esac
DOCKER
chmod +x "$evidence/bin/docker"
export CONTAINER="$evidence/container"
export PATH="$evidence/bin:$PATH"
run_case() {
  local name=$1 expected=$2 outcome=${3:-failure}
  mkdir -p "$evidence/$name/test/expected"
  cp "$evidence/mock-sb" "$evidence/$name/sb"
  cp "$evidence/expected/$isolated" "$evidence/$name/test/expected/$isolated"
  if [[ $name != missing-expected ]]; then
    cp "$evidence/expected/$shared" "$evidence/$name/test/expected/$shared"
  fi
  export MODE=$name CALLS="$evidence/$name/calls"
  : > "$CALLS"
  if [[ $name == cumulative ]]; then
    printf 'not ok 127 - earlier_shared_failure\nok 1 - isolated_child\n' > "$evidence/$name/test/regression.out"
  elif [[ $name == unreadable-host ]]; then
    printf 'unreadable summary\n' > "$evidence/$name/test/regression.out"
    chmod 000 "$evidence/$name/test/regression.out"
  fi
  local status=0 diff_status=0
  (cd "$evidence/$name" && bash -euo pipefail "$evidence/plans.sh") > "$evidence/$name/console.log" 2>&1 || status=$?
  if [[ $outcome == failure ]]; then
    (cd "$evidence/$name" && bash -euo pipefail "$evidence/diffs.sh") >> "$evidence/$name/console.log" 2>&1 || diff_status=$?
    if [[ $diff_status -ne 0 ]]; then status=$diff_status; fi
  fi
  printf '%s\n' "$status" > "$evidence/$name/exit-status"
  if [[ $expected == nonzero ]]; then
    [[ $status -ne 0 ]] || { echo "$name: expected failure" >&2; exit 1; }
  else
    [[ $status -eq $expected ]] || { echo "$name: expected exit $expected, got $status" >&2; exit 1; }
  fi
}
expected_diff="$evidence/expected-shared.diff"
{
  printf '%s\n' "--- test/expected/$shared" "+++ db:/statbus/test/results/$shared"
  printf '%s\n' '@@ -1 +1 @@' '-expected shared output' '+actual earlier shared mismatch'
} > "$expected_diff"
assert_results() {
  local name=$1 dir="$evidence/$1/tmp/fast-ci-regression"
  diff -r "$CONTAINER/results" "$dir/results"
  cmp "$CONTAINER/results.tar" "$dir/results.tar"
  cmp "$expected_diff" "$dir/diffs/$shared.diff"
  cmp /dev/null "$dir/diffs/$isolated.diff"
  [[ -O "$dir/results/$shared" && -r "$dir/results/$shared" ]]
  # Compare the exact named printed mismatch, independent of preceding raw logs.
  awk -v marker="=== per-test diff: $shared ===" '$0 == marker { active=1; next } active {print}' "$evidence/$name/console.log" > "$evidence/$name/printed-shared.diff"
  cmp "$expected_diff" "$evidence/$name/printed-shared.diff"
}
# This is the regression: no host/shared summary and the passing child removed
# both container summaries, yet every prior result byte and shared diff survive.
run_case recovery 1
assert_results recovery
cmp /dev/null "$evidence/recovery/tmp/fast-ci-regression/regression.out"
cmp "$CONTAINER/postgres.log" "$evidence/recovery/tmp/fast-ci-regression/postgres.log"
printf '0\n' | cmp - "$evidence/recovery/tmp/fast-ci-regression/postgres.log.status"
printf 'fixture: summary missing after passing isolated child\n' | cmp - "$evidence/recovery/tmp/fast-ci-regression/regression.out.stderr"
printf 'fixture: diff missing after passing isolated child\n' | cmp - "$evidence/recovery/tmp/fast-ci-regression/regression.diffs.stderr"
echo 'PASS: earlier shared SQL374 exact named mismatch recovered after passing isolated child removed both summaries'
run_case normal 0
assert_results normal
for file in regression.out regression.diffs; do
  cmp "$CONTAINER/$file" "$evidence/normal/tmp/fast-ci-regression/$file"
done
printf 'compose logs --no-color db\ncat /statbus/test/regression.out\ncat /statbus/test/regression.diffs\ntar -cf - -C /statbus/test results\n' > "$evidence/expected-calls"
cmp "$evidence/expected-calls" "$evidence/normal/calls"
echo 'PASS: diff exit1 is expected mismatch, all archived/extracted result bytes retained as readable runner-owned files'
run_case cumulative 0
assert_results cumulative
cmp "$evidence/cumulative/test/regression.out" "$evidence/cumulative/tmp/fast-ci-regression/host-regression.out"
run_case unreadable-host 0
assert_results unreadable-host
# Actual permission refusal is only observable when this test is not root.
if [[ ! -r "$evidence/unreadable-host/test/regression.out" ]]; then
  grep -Fx 'Host pg_regress summary unreadable or absent; collecting container results.' "$evidence/unreadable-host/console.log"
fi
echo 'PASS: readable cumulative host TAP retained; unreadable or absent summary does not block result recovery'
run_case missing-summary 1
assert_results missing-summary
run_case missing-diff 1
assert_results missing-diff
run_case unavailable 42
run_case partial 43
assert_results partial
printf 'partial diff bytes\n' | cmp - "$evidence/partial/tmp/fast-ci-regression/regression.diffs"
run_case archive-error 44
run_case archive-partial 45
assert_results archive-partial
run_case corrupt-archive nonzero
run_case empty-results 1
cmp "$evidence/empty/results/incomplete.txt" "$evidence/empty-results/tmp/fast-ci-regression/results/incomplete.txt"
run_case missing-expected 2
cmp "$CONTAINER/results/$shared" "$evidence/missing-expected/tmp/fast-ci-regression/results/$shared"
test -s "$evidence/missing-expected/tmp/fast-ci-regression/diffs/$shared.stderr"
for name in recovery cumulative unreadable-host missing-summary missing-diff unavailable partial archive-error archive-partial corrupt-archive empty-results missing-expected; do
  cmp "$evidence/expected-calls" "$evidence/$name/calls"
done
echo 'PASS: collection/archive/extraction errors fail with retained bytes; missing expected file preserves unexpected diff exit2'
run_case log-failure 71
assert_results log-failure
cmp "$CONTAINER/postgres.log" "$evidence/log-failure/tmp/fast-ci-regression/postgres.log"
printf 'fixture: log transport failed\n' | cmp - "$evidence/log-failure/tmp/fast-ci-regression/postgres.log.stderr"
printf '71\n' | cmp - "$evidence/log-failure/tmp/fast-ci-regression/postgres.log.status"
cmp "$evidence/expected-calls" "$evidence/log-failure/calls"
run_case privacy 0
assert_results privacy
printf '%s\n' 'db | SQL literal: [REDACTED] [REDACTED] [REDACTED JWT]' | cmp - "$evidence/privacy/tmp/fast-ci-regression/postgres.log"
printf 'fixture stderr: [REDACTED]\n' | cmp - "$evidence/privacy/tmp/fast-ci-regression/postgres.log.stderr"
run_case config-error 49
assert_results config-error
printf 'Cannot read CI configuration for log redaction.\n' | cmp - "$evidence/config-error/tmp/fast-ci-regression/postgres.log.stderr"
printf '49\n' | cmp - "$evidence/config-error/tmp/fast-ci-regression/postgres.log.status"
run_case config-incomplete 1
assert_results config-incomplete
printf 'Cannot read CI configuration for log redaction.\n' | cmp - "$evidence/config-incomplete/tmp/fast-ci-regression/postgres.log.stderr"
echo 'PASS: exact server plan bytes retained; transport stderr/status preserved while results recover; literal config secrets/JWTs redacted and unsafe config reads fail closed'
run_case success 0 success
cmp "$CONTAINER/postgres.log" "$evidence/success/tmp/fast-ci-regression/postgres.log"
printf '0\n' | cmp - "$evidence/success/tmp/fast-ci-regression/postgres.log.status"
printf 'compose logs --no-color db\n' | cmp - "$evidence/success/calls"
run_case success-log-failure 71 success
cmp "$CONTAINER/postgres.log" "$evidence/success-log-failure/tmp/fast-ci-regression/postgres.log"
printf 'fixture: log transport failed\n' | cmp - "$evidence/success-log-failure/tmp/fast-ci-regression/postgres.log.stderr"
printf '71\n' | cmp - "$evidence/success-log-failure/tmp/fast-ci-regression/postgres.log.status"
printf 'compose logs --no-color db\n' | cmp - "$evidence/success-log-failure/calls"
echo 'PASS: passing SQL retains exact plan bytes; log transport failure retains partial bytes/stderr/status independently of SQL outcome'
real_tee=$(command -v tee)
export REAL_TEE="$real_tee"
cat > "$evidence/bin/tee" <<'TEE'
#!/usr/bin/env bash
"$REAL_TEE" "$@"
exit 74
TEE
chmod +x "$evidence/bin/tee"
run_case sink-error 74
assert_results sink-error
echo 'PASS: sink errors stay failures without preventing per-test evidence recovery'
# Declarative scheduling proof, not a claim of real GitHub artifact upload.
ruby -ryaml -e '
  steps = YAML.load_file(ARGV[0]).fetch("jobs").values.flat_map { |j| j.fetch("steps", []) }
  capture = steps.index { |s| s["name"] == "Show regression diffs on failure" }
  upload = steps.index { |s| s["name"] == "Upload regression diagnostics" }
  cleanup = steps.index { |s| s["name"] == "Cleanup" }
  plans = steps.index { |s| s["name"] == "Capture PostgreSQL plans" }
  sql = steps.index { |s| s["id"] == "sql_tests" }
  raise "capture/upload/cleanup order" unless sql < plans && plans < capture && capture < upload && upload < cleanup
  both = "always() && (steps.sql_tests.outcome == '\''success'\'' || steps.sql_tests.outcome == '\''failure'\'')"
  raise "capture plans after success/failure" unless steps[plans]["if"] == both
  raise "failure diff recovery after log collection error" unless steps[capture]["if"] == "always() && steps.sql_tests.outcome == '\''failure'\''"
  s = steps[upload]
  raise "upload after success/failure and collection failure" unless s["if"] == both
  raise "artifact action" unless s["uses"] == "actions/upload-artifact@v4"
  raise "artifact includes results archive/extraction/diffs" unless s.fetch("with")["path"] == "tmp/fast-ci-regression/"
  raise "missing artifact must fail" unless s.fetch("with")["if-no-files-found"] == "error"
' "$workflow"
echo 'PASS: archive, all extracted results and per-test diffs fall under always-upload root before cleanup'

# Execute the separate profiling step with a stateful, refusing psql transport.
# This validates emitted SQL/settings and fresh connections, not a real ALTER SYSTEM.
awk '
  /^      - name: Enable nested slow-query plans$/ { step=1; next }
  step && /^        run: \|$/ { body=1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$workflow" > "$evidence/profile.sh"
test -s "$evidence/profile.sh"
bash -n "$evidence/profile.sh"
mkdir -p "$evidence/profile-bin"
cat > "$evidence/profile-bin/docker" <<'PROFILE'
#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import sys
root = Path(os.environ['PROFILE_STATE'])
mode = os.environ['PROFILE_MODE']
base = ['compose', 'exec', '-T', 'db', 'psql', '-X', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
assert sys.argv[1:] in (base, base + ['-At']), 'refused psql transport'
sql = sys.stdin.read()
count_file = root / 'calls'
count = int(count_file.read_text()) + 1 if count_file.exists() else 1
count_file.write_text(str(count))
(root / f'connection-{count}.sql').write_text(sql)
expected = {
    'session_preload_libraries': 'safeupdate,auto_explain',
    'auto_explain.log_min_duration': '1000ms',
    'auto_explain.log_nested_statements': 'on',
    'auto_explain.log_analyze': 'on',
    'auto_explain.log_timing': 'off',
    'auto_explain.log_parameter_max_length': '0',
    'log_parameter_max_length': '0',
    'log_parameter_max_length_on_error': '0',
}
if sys.argv[1:] == base:
    if mode == 'configure-failure':
        print('fixture: configuration transport failed', file=sys.stderr)
        sys.exit(47)
    assert sql.startswith("LOAD 'auto_explain';\n"), 'LOAD must register real GUCs first'
    settings = dict(re.findall(r"ALTER SYSTEM SET ([\w.]+) = '([^']+)';", sql))
    assert settings == expected, 'exact requested instrumentation/privacy settings'
    assert 'SELECT pg_reload_conf() AS reloaded \\gset' in sql
    assert '\\if :reloaded' in sql and '\\quit 1' in sql
    (root / 'settings.json').write_text(json.dumps(settings))
else:
    if mode == 'verify-failure':
        print('fixture: verification transport failed', file=sys.stderr)
        sys.exit(48)
    assert (root / 'settings.json').exists(), 'configuration must precede new connection'
    assert 'FROM requested LEFT JOIN pg_settings USING (name)' in sql
    names = re.findall(r"\(\d, '([^']+)'\)", sql)
    assert names == list(expected), 'verify every real registered setting in order'
    settings = json.loads((root / 'settings.json').read_text())
    settings['auto_explain.log_min_duration'] = '1000'
    values = [settings[name] for name in names]
    if mode == 'mismatch' or (mode == 'reload-delay' and count == 2):
        values[0] = '<missing>'
    print('|'.join(values))
PROFILE
printf '#!/usr/bin/env bash\n[[ "$*" == 1 ]] || exit 97\n' > "$evidence/profile-bin/sleep"
chmod +x "$evidence/profile-bin/docker" "$evidence/profile-bin/sleep"
for case in normal reload-delay mismatch configure-failure verify-failure; do
  mkdir -p "$evidence/profile-$case"
  status=0
  PROFILE_MODE="$case" PROFILE_STATE="$evidence/profile-$case" PATH="$evidence/profile-bin:$PATH" \
    bash -euo pipefail "$evidence/profile.sh" > "$evidence/profile-$case/console.log" 2>&1 || status=$?
  case "$case" in
    normal) expected_status=0; expected_calls=2 ;;
    reload-delay) expected_status=0; expected_calls=3 ;;
    mismatch) expected_status=1; expected_calls=11 ;;
    configure-failure) expected_status=47; expected_calls=1 ;;
    verify-failure) expected_status=48; expected_calls=2 ;;
  esac
  [[ $status -eq $expected_status ]]
  [[ $(cat "$evidence/profile-$case/calls") -eq $expected_calls ]]
done
ruby -ryaml -e '
  steps = YAML.load_file(ARGV[0]).fetch("jobs").fetch("fast-tests").fetch("steps")
  profile = steps.index { |s| s["name"] == "Enable nested slow-query plans" }
  sql = steps.index { |s| s["id"] == "sql_tests" }
  raise "profile must precede SQL suite" unless profile < sql
  raise "SQL outcome remains strict" unless steps[sql]["run"] == "set -euxo pipefail\n./dev.sh migrate-and-test fast\n"
' "$workflow"
echo 'PASS: profiling LOAD/ALTER SYSTEM/reload and fresh-connection settings verified; transport errors fail and reload visibility retry is bounded'
