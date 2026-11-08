#!/usr/bin/env bash
# Execute the workflow's unchanged diagnostic shell body with a refusing Docker
# double. No daemon, database, network, or dev.sh bootstrap is invoked.
set -euo pipefail
workflow=${1:-.github/workflows/fast-tests.yaml}
evidence=${2:?usage: bash test/fast-ci-regression-diagnostics-test.sh workflow retained-evidence-dir}
workflow=$(cd "$(dirname "$workflow")" && pwd)/$(basename "$workflow")
mkdir -p "$evidence"
evidence=$(cd "$evidence" && pwd)
evidence=$(mktemp -d "$evidence/run.XXXXXX")
printf 'Evidence: %s\n' "$evidence"
mkdir -p "$evidence/bin" "$evidence/container"
awk '
  /^      - name: Show regression diffs on failure$/ { step=1; next }
  step && /^        run: \|$/ { body=1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$workflow" > "$evidence/body.sh"
test -s "$evidence/body.sh"
bash -n "$evidence/body.sh"
printf 'not ok 127 - fixture_sql374\n1..131\n' > "$evidence/container/regression.out"
printf '%s\n' '--- expected/fixture_sql374.out' '+++ results/fixture_sql374.out' '-expected fixture' '+actual fixture' > "$evidence/container/regression.diffs"
cat > "$evidence/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 8 && "$1 $2 $3 $4 $5 $6 $7" == 'compose exec -T --workdir /statbus db cat' ]] || exit 97
printf '%s\n' "$8" >> "$CALLS"
file=${8##*/}
case "$MODE:$file" in
  unavailable:*) echo 'fixture: db unavailable' >&2; exit 42 ;;
  missing-summary:regression.out) echo 'fixture: summary missing' >&2; exit 1 ;;
  missing-diff:regression.diffs) echo 'fixture: diff missing' >&2; exit 1 ;;
  partial:regression.diffs) printf 'partial diff bytes\n'; echo 'fixture: stream interrupted' >&2; exit 43 ;;
esac
cat "$CONTAINER/$file"
DOCKER
chmod +x "$evidence/bin/docker"
export CONTAINER="$evidence/container"
export PATH="$evidence/bin:$PATH"
run_case() {
  local name=$1 expected=$2
  mkdir -p "$evidence/$name/test"
  export MODE=$name CALLS="$evidence/$name/calls"
  : > "$CALLS"
  if [[ $name == cumulative ]]; then
    printf 'not ok 127 - earlier_shared_failure\nok 1 - isolated_child\n' > "$evidence/$name/test/regression.out"
  fi
  local status=0
  (cd "$evidence/$name" && bash -euo pipefail "$evidence/body.sh") > "$evidence/$name/console.log" 2>&1 || status=$?
  printf '%s\n' "$status" > "$evidence/$name/exit-status"
  [[ $status -eq $expected ]] || { echo "$name: expected exit $expected, got $status" >&2; exit 1; }
}
run_case normal 0
# Positive acceptance: exact producer bytes retained and printed, despite no
# host summary. This assertion fails against the original host-only branch.
for file in regression.out regression.diffs; do
  cmp "$CONTAINER/$file" "$evidence/normal/tmp/fast-ci-regression/$file"
done
{
  printf '=== db:/statbus/test/regression.out ===\n'
  cat "$CONTAINER/regression.out"
  printf '=== db:/statbus/test/regression.diffs ===\n'
  cat "$CONTAINER/regression.diffs"
} > "$evidence/normal/expected-console.log"
cmp "$evidence/normal/expected-console.log" "$evidence/normal/console.log"
printf '/statbus/test/regression.out\n/statbus/test/regression.diffs\n' > "$evidence/expected-calls"
cmp "$evidence/expected-calls" "$evidence/normal/calls"
echo 'PASS: absent host summary still retrieves and prints exact container summary/diff'
run_case cumulative 0
cmp "$evidence/cumulative/test/regression.out" "$evidence/cumulative/tmp/fast-ci-regression/host-regression.out"
for file in regression.out regression.diffs; do
  cmp "$CONTAINER/$file" "$evidence/cumulative/tmp/fast-ci-regression/$file"
done
echo 'PASS: whole-run host TAP and last-container diagnostics both retained'
run_case missing-summary 1
cmp "$CONTAINER/regression.diffs" "$evidence/missing-summary/tmp/fast-ci-regression/regression.diffs"
printf 'fixture: summary missing\n' | cmp - "$evidence/missing-summary/tmp/fast-ci-regression/regression.out.stderr"
run_case missing-diff 1
cmp "$CONTAINER/regression.out" "$evidence/missing-diff/tmp/fast-ci-regression/regression.out"
run_case unavailable 42
run_case partial 43
printf 'partial diff bytes\n' | cmp - "$evidence/partial/tmp/fast-ci-regression/regression.diffs"
printf 'fixture: stream interrupted\n' | cmp - "$evidence/partial/tmp/fast-ci-regression/regression.diffs.stderr"
for name in missing-summary missing-diff unavailable partial; do
  cmp "$evidence/expected-calls" "$evidence/$name/calls"
done
echo 'PASS: missing files, unavailable db and interrupted stream fail with retained evidence and both retrievals attempted'
# Exercise pipefail, not merely a Docker error. The normal tee still writes.
real_tee=$(command -v tee)
export REAL_TEE="$real_tee"
cat > "$evidence/bin/tee" <<'TEE'
#!/usr/bin/env bash
"$REAL_TEE" "$@"
exit 74
TEE
chmod +x "$evidence/bin/tee"
run_case sink-error 74
cmp "$CONTAINER/regression.diffs" "$evidence/sink-error/tmp/fast-ci-regression/regression.diffs"
echo 'PASS: evidence sink errors remain failures'
# Validate the declarative upload contract, not a claim of a real GitHub upload.
ruby -ryaml -e '
  steps = YAML.load_file(ARGV[0]).fetch("jobs").values.flat_map { |j| j.fetch("steps", []) }
  capture = steps.index { |s| s["name"] == "Show regression diffs on failure" }
  upload = steps.index { |s| s["name"] == "Upload regression diagnostics" }
  cleanup = steps.index { |s| s["name"] == "Cleanup" }
  raise "capture/upload/cleanup order" unless capture < upload && upload < cleanup
  s = steps[upload]
  raise "upload must run after collection failure" unless s["if"] == "always() && steps.sql_tests.outcome == '\''failure'\''"
  raise "artifact action" unless s["uses"] == "actions/upload-artifact@v4"
  raise "artifact evidence path" unless s.fetch("with")["path"] == "tmp/fast-ci-regression/"
  raise "missing artifact must fail" unless s.fetch("with")["if-no-files-found"] == "error"
' "$workflow"
echo 'PASS: always-upload contract targets retained evidence before cleanup'
