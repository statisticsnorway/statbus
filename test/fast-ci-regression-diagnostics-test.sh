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
' "$workflow" > "$evidence/body.sh"
test -s "$evidence/body.sh"
bash -n "$evidence/body.sh"
shared=374_statbus_591_power_group_processing_scales_with_relationships.out
isolated=094_read_only_window_worker_recovery_exemption.out
printf 'expected shared output\n' > "$evidence/expected/$shared"
printf 'actual earlier shared mismatch\n' > "$evidence/container/results/$shared"
printf 'passing isolated output\n' > "$evidence/expected/$isolated"
cp "$evidence/expected/$isolated" "$evidence/container/results/$isolated"
printf 'auxiliary\000result bytes\377\n' > "$evidence/container/results/nested/opaque.bin"
printf 'ok 1 - 094_read_only_window_worker_recovery_exemption\n1..1\n' > "$evidence/container/regression.out"
printf 'last invocation raw diagnostic\n' > "$evidence/container/regression.diffs"
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
  local name=$1 expected=$2
  mkdir -p "$evidence/$name/test/expected"
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
  local status=0
  (cd "$evidence/$name" && bash -euo pipefail "$evidence/body.sh") > "$evidence/$name/console.log" 2>&1 || status=$?
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
printf 'fixture: summary missing after passing isolated child\n' | cmp - "$evidence/recovery/tmp/fast-ci-regression/regression.out.stderr"
printf 'fixture: diff missing after passing isolated child\n' | cmp - "$evidence/recovery/tmp/fast-ci-regression/regression.diffs.stderr"
echo 'PASS: earlier shared SQL374 exact named mismatch recovered after passing isolated child removed both summaries'
run_case normal 0
assert_results normal
for file in regression.out regression.diffs; do
  cmp "$CONTAINER/$file" "$evidence/normal/tmp/fast-ci-regression/$file"
done
printf 'cat /statbus/test/regression.out\ncat /statbus/test/regression.diffs\ntar -cf - -C /statbus/test results\n' > "$evidence/expected-calls"
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
  raise "capture/upload/cleanup order" unless capture < upload && upload < cleanup
  s = steps[upload]
  raise "upload after collection failure" unless s["if"] == "always() && steps.sql_tests.outcome == '\''failure'\''"
  raise "artifact action" unless s["uses"] == "actions/upload-artifact@v4"
  raise "artifact includes results archive/extraction/diffs" unless s.fetch("with")["path"] == "tmp/fast-ci-regression/"
  raise "missing artifact must fail" unless s.fetch("with")["if-no-files-found"] == "error"
' "$workflow"
echo 'PASS: archive, all extracted results and per-test diffs fall under always-upload root before cleanup'
