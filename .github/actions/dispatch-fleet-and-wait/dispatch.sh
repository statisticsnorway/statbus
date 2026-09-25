#!/usr/bin/env bash
set -euo pipefail

FLEET_GROUP=hetzner-vm-fleet

is_paid_fleet_workflow() {
  case "$1" in
    test-smoke.yaml|install-recovery-harness.yaml|upgrade-arc-harness.yaml) return 0 ;;
    *) return 1 ;;
  esac
}

fleet_group_json() {
  local err_file output
  err_file="$(mktemp)"
  if output="$(gh api "repos/${GH_REPO}/actions/concurrency_groups/${FLEET_GROUP}" 2>"$err_file")"; then
    rm -f "$err_file"
    printf '%s\n' "$output"
    return 0
  fi
  if grep -q 'HTTP 404' "$err_file"; then
    rm -f "$err_file"
    jq -nc \
      --arg group_name "$FLEET_GROUP" \
      --arg group_url "https://api.github.com/repos/${GH_REPO}/actions/concurrency_groups/${FLEET_GROUP}" \
      '{group_name:$group_name, group_url:$group_url, total_count:0, group_members:[]}'
    return 0
  fi
  cat "$err_file" >&2
  rm -f "$err_file"
  return 1
}

# GitHub's documented response is ordered owner-first under group_members. A
# successful response is authoritative only when every member is structurally
# usable. Only the explicit 404 path above means an empty group.
fleet_members() {
  local json
  json="$(cat)"
  jq -e --arg expected_group "$FLEET_GROUP" '
    type == "object" and
    .group_name == $expected_group and
    (.group_url | type) == "string" and
    (.group_url | test("^https://[^[:space:]]+$")) and
    (.total_count | type) == "number" and
    (.total_count | floor) == .total_count and .total_count >= 0 and
    (.group_members | type) == "array" and
    .total_count == (.group_members | length) and
    all(.group_members[];
      has("run_id") and has("run_name") and has("run_url") and
      has("run_html_url") and has("status") and
      (.run_id | type) == "number" and (.run_id | floor) == .run_id and .run_id > 0 and
      (.run_name | type) == "string" and (.run_name | length) > 0 and
      (.status == "in_progress" or .status == "pending") and
      (.run_url == null or ((.run_url | type) == "string" and (.run_url | test("^https://[^[:space:]]+$")))) and
      (.run_html_url == null or ((.run_html_url | type) == "string" and (.run_html_url | test("^https://[^[:space:]]+$")))))
  ' <<<"$json" >/dev/null || {
    echo "::error title=Malformed fleet concurrency response::successful API response does not match GitHub's required concurrency-group envelope and member schema" >&2
    return 1
  }
  jq -c '.group_members | to_entries[] |
    {id:.value.run_id, name:.value.run_name, status:.value.status,
     url:(.value.run_html_url // .value.run_url // "<unavailable>"), order:(.key + 1)}' <<<"$json"
}

describe_members() {
  local json=$1
  local rows
  rows="$(fleet_members <<<"$json")"
  [ -n "$rows" ] || { echo "  <empty>"; return; }
  while IFS= read -r row; do
    jq -r '"  order=\(.order) id=\(.id) name=\(.name) status=\(.status) url=\(.url)"' <<<"$row"
  done <<<"$rows"
}

# The REST run has no workflow_dispatch inputs (including orchestrator-run-id).
# The release orchestrator dispatches with GITHUB_TOKEN, whose child actor is
# github-actions[bot]; a human's direct dispatch has their own actor. Unknown
# provenance fails closed. Compare the actual run ref, not its cosmetic name.
classify_fleet_member() {
  local row=$1 id run branch sha actor event
  id="$(jq -r '.id' <<<"$row")"
  if ! run="$(gh api "repos/${GH_REPO}/actions/runs/${id}")"; then
    echo refuse
    return
  fi
  if ! jq -e --argjson id "$id" '
    .id == $id and (.head_branch | type) == "string" and
    (.head_sha | type) == "string" and (.event | type) == "string" and
    (.actor.login | type) == "string"
  ' <<<"$run" >/dev/null; then
    echo refuse
    return
  fi
  read -r branch sha event actor < <(jq -r '[.head_branch,.head_sha,.event,.actor.login] | join(" ")' <<<"$run")
  if [ "$event" != workflow_dispatch ] || [ "$actor" != 'github-actions[bot]' ] ||
    ! [[ "$REF" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] ||
    ! [[ "$branch" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]]; then
    echo refuse
  elif [ "$branch" != "$REF" ]; then
    if [ "$(printf '%s\n%s\n' "$branch" "$REF" | LC_ALL=C sort -V | head -n 1)" = "$branch" ]; then
      echo wait
    else
      echo refuse
    fi
  elif [ "$sha" != "$COMMIT_SHA" ] && git merge-base --is-ancestor "$sha" "$COMMIT_SHA"; then
    echo wait
  else
    echo refuse
  fi
}

preflight_fleet_group() {
  local json rows row id remaining elapsed start=$SECONDS waited=false
  while :; do
    json="$(fleet_group_json)"
    rows="$(fleet_members <<<"$json")"
    if [ -z "$rows" ]; then
      if [ "$waited" = true ]; then
        echo "Fleet drained; dispatching ${WORKFLOW_FILE} at ${REF}."
        echo "- Fleet drained after $((SECONDS - start))s; dispatching \`${WORKFLOW_FILE}\` at \`${REF}\`." >> "$GITHUB_STEP_SUMMARY"
      fi
      return 0
    fi
    while IFS= read -r row; do
      if [ "$(classify_fleet_member "$row")" != wait ]; then
        echo "::error title=Hetzner VM fleet occupied::refusing to dispatch ${WORKFLOW_FILE}; ordered owner and waiters follow"
        describe_members "$json"
        return 1
      fi
    done <<<"$rows"
    elapsed=$((SECONDS - start))
    if [ "$elapsed" -ge 1200 ]; then
      echo "::error title=Fleet drain timed out::older fleet still occupied after 20 minutes; refusing to dispatch ${WORKFLOW_FILE}"
      describe_members "$json"
      echo "- Fleet drain timed out after ${elapsed}s; \`${WORKFLOW_FILE}\` not dispatched." >> "$GITHUB_STEP_SUMMARY"
      return 1
    fi
    waited=true
    id="$(jq -r '.id' <<<"$rows" | head -n 1)"
    remaining="$(gh run view "$id" --json jobs --jq '[.jobs[] | select(.status != "completed") | .name] | join(", ")' 2>/dev/null || echo '<unavailable>')"
    echo "Waiting for superseded fleet owner ${id} to drain (${elapsed}s/1200s); remaining jobs: ${remaining:-<group releasing>}"
    describe_members "$json"
    echo "- Waiting for older fleet owner [${id}](https://github.com/${GH_REPO}/actions/runs/${id}) to drain (${elapsed}s/1200s); remaining jobs: ${remaining:-<group releasing>}." >> "$GITHUB_STEP_SUMMARY"
    sleep 30
  done
}

report_fleet_group_after_correlation() {
  local our_id=$1 json rows
  json="$(fleet_group_json)"
  rows="$(fleet_members <<<"$json")"
  jq -e --argjson id "$our_id" 'select(.id == $id)' <<<"$rows" >/dev/null || return 0
  echo "Native fleet queue membership after correlating run ${our_id}; continuing to poll without automatic cancellation:"
  describe_members "$json"
}

if [ "${STATBUS_DISPATCH_TEST_MODE:-}" = classify ]; then
  is_paid_fleet_workflow "$WORKFLOW_FILE"
  exit $?
fi
if [ "${STATBUS_DISPATCH_TEST_MODE:-}" = classify-member ]; then
  classify_fleet_member "$(cat)"
  exit 0
fi
if [ "${STATBUS_DISPATCH_TEST_MODE:-}" = preflight ]; then
  preflight_fleet_group
  exit $?
fi
if [ "${STATBUS_DISPATCH_TEST_MODE:-}" = postflight ]; then
  report_fleet_group_after_correlation "${RUN_ID:-}"
  exit $?
fi

if is_paid_fleet_workflow "$WORKFLOW_FILE"; then
  preflight_fleet_group
fi

# SNAPSHOT (STATBUS-214 architect amendment): capture the ids of
# every existing workflow_dispatch run of this workflow at this
# commit BEFORE dispatching, so the run we start can be found by
# set difference rather than by timestamp. A timestamp heuristic
# (sort_by(.createdAt) | last) picks the WRONG run in exactly the
# case it can go wrong: OUR dispatch is the FIRST one issued after
# a snapshot timestamp, so among competing candidates ours is the
# OLDEST, not the newest — `last` would preferentially select a
# competing dispatch instead of ours.
before_ids="$(gh run list --workflow="$WORKFLOW_FILE" --commit="$COMMIT_SHA" \
  --event=workflow_dispatch --json databaseId --jq '.[].databaseId' | sort)"

echo "Dispatching ${WORKFLOW_FILE} at ${REF} (commit ${COMMIT_SHA})..."

# RETRY: mirrors upgrade-arc-harness.yaml's dispatch_images — ref
# propagation after a tag push is eventually consistent; a dispatch
# fired immediately can transiently 404/422 "no ref found". Retry,
# don't red the whole chain on a timing hiccup.
# Build the -f arguments once. Read as an array so a value containing
# spaces stays one argument; an empty DISPATCH_INPUTS yields no args at
# all, which is byte-identical to the previous behaviour for the callers
# that pass none.
dispatch_args=()
while IFS= read -r kv; do
  [ -n "$kv" ] || continue
  case "$kv" in
    *=*) dispatch_args+=(-f "$kv") ;;
    *)
      echo "::error title=Malformed dispatch input::expected key=value, got '${kv}'"
      exit 1
      ;;
  esac
done <<< "$DISPATCH_INPUTS"
if is_paid_fleet_workflow "$WORKFLOW_FILE"; then
  dispatch_args+=(-f "orchestrator-run-id=${GITHUB_RUN_ID}")
fi
# Same set -u caution as the expansion below: ${#arr[@]} on an empty
# array is also an unbound-variable error on bash < 4.4, so the summary
# is driven by the raw input rather than by the array's length.
if [ -n "${DISPATCH_INPUTS//[[:space:]]/}" ]; then
  echo "Dispatch inputs: $(printf '%s ' ${dispatch_args[@]+"${dispatch_args[@]}"})"
fi

dispatched=0
for attempt in 1 2 3 4 5 6; do
  # ${arr[@]+"${arr[@]}"} — not "${arr[@]}". Under `set -u` an EMPTY array
  # expansion is an unbound-variable error on bash < 4.4, and every
  # existing caller passes no inputs, so the plain form would fail
  # exactly the callers this change is supposed to leave untouched.
  if gh workflow run "$WORKFLOW_FILE" --ref "$REF" ${dispatch_args[@]+"${dispatch_args[@]}"}; then
    dispatched=1
    echo "Dispatched ${WORKFLOW_FILE} (attempt ${attempt})."
    break
  fi
  echo "  dispatch failed (attempt ${attempt}/6) — ref not propagated yet? retrying in 10s..."
  sleep 10
done
if [ "$dispatched" -ne 1 ]; then
  echo "::error title=Fleet dispatch failed::could not dispatch ${WORKFLOW_FILE} at ${REF} after 6 attempts"
  exit 1
fi

# CORRELATE: `gh workflow run` reports no id for the run it just
# created (a documented GitHub API gap). Set difference against the
# before_ids snapshot above, NOT a timestamp heuristic (see the
# comment on that snapshot). Exactly one new id is ours. Zero new
# ids: keep polling. MORE than one: genuinely ambiguous (a stray
# manual dispatch racing us at the exact same commit) — fail loud
# naming every candidate rather than guess. A silently
# mis-correlated poll would watch a stranger's run, report GREEN on
# ITS verdict, and move the chain on while our own run is still in
# flight or failing — the one property this orchestrator exists to
# provide.
echo "Locating the dispatched run (set difference against the pre-dispatch snapshot)..."
run_id=""
for attempt in $(seq 1 24); do   # up to ~4min at 10s
  after_ids="$(gh run list --workflow="$WORKFLOW_FILE" --commit="$COMMIT_SHA" \
    --event=workflow_dispatch --json databaseId --jq '.[].databaseId' | sort)"
  new_ids="$(comm -13 <(printf '%s\n' "$before_ids" | grep -v '^$') <(printf '%s\n' "$after_ids" | grep -v '^$'))"
  new_count=0
  [ -n "$new_ids" ] && new_count="$(printf '%s\n' "$new_ids" | grep -c .)"
  if [ "$new_count" -eq 1 ]; then
    run_id="$new_ids"
    break
  elif [ "$new_count" -gt 1 ]; then
    echo "::error title=Ambiguous fleet dispatch correlation::more than one new ${WORKFLOW_FILE} run appeared at commit ${COMMIT_SHA} after dispatch — cannot tell which is ours. New run ids: $(tr '\n' ' ' <<< "$new_ids")"
    exit 1
  fi
  echo "  run not visible yet (attempt ${attempt}/24, 0 new runs so far) — retrying in 10s..."
  sleep 10
done
if [ -z "$run_id" ]; then
  echo "::error title=Fleet run not found::dispatched ${WORKFLOW_FILE} at ${REF} but no new run appeared within 4 minutes (commit=${COMMIT_SHA})"
  exit 1
fi
run_url="$(gh run view "$run_id" --json url --jq .url)"
echo "run_url=${run_url}" >> "$GITHUB_OUTPUT"
echo "Found run: ${run_url} (id ${run_id})"

# The preflight is intentionally outside GitHub's atomic admission boundary. A
# rare race therefore waits in the native queue. Report the exact ordered group
# membership and keep polling. The child revalidates the parent and newest RC
# before its first side effect, so a stale waiter cannot later spend money.
if is_paid_fleet_workflow "$WORKFLOW_FILE"; then
  report_fleet_group_after_correlation "$run_id"
fi

# POLL TO CONCLUSION: never `gh run watch --exit-status` — it has
# returned 0 for a FAILED run in this org's own deploy history
# (CLAUDE.md). Poll status and branch on conclusion explicitly,
# same pattern as deploy-to-dev.yaml's images-ready gate.
start=$SECONDS
while :; do
  read -r run_status run_conclusion < <(gh run view "$run_id" --json status,conclusion --jq '"\(.status) \(.conclusion // "pending")"')
  if [ "$run_status" = "completed" ]; then
    # workflow_dispatch does not expose the child's job outputs to this parent.
    # The child aggregate uploads one verdict artifact after ALL matrix jobs.
    # Never call a missing verdict green. Early discovery/checkout failures may
    # have no artifact; their non-success conclusion still reports the failure.
    if is_paid_fleet_workflow "$WORKFLOW_FILE"; then
      verdict_dir="$(mktemp -d)"
      if gh run download "$run_id" --name fleet-verdict --dir "$verdict_dir" >/dev/null 2>&1; then
        verdict="$(cat "$verdict_dir/fleet-verdict.txt" 2>/dev/null || true)"
      else
        verdict=""
      fi
      rm -rf "$verdict_dir"
      case "$verdict" in
        SUPERSEDED)
          echo 'superseded=true' >> "$GITHUB_OUTPUT"
          echo "SUPERSEDED — ${WORKFLOW_FILE} stopped a scenario before its VM boot: ${run_url}"
          exit 0 ;;
        COMPLETE) echo 'superseded=false' >> "$GITHUB_OUTPUT" ;;
        *)
          if [ "$run_conclusion" = success ]; then
            echo "::error title=Missing fleet verdict::${WORKFLOW_FILE} concluded success without a verifiable aggregate artifact: ${run_url}"
            exit 1
          fi
          echo "No aggregate verdict (early child failure); preserving conclusion '${run_conclusion}'."
          ;;
      esac
    fi
    if [ "$run_conclusion" = "success" ]; then
      echo "GREEN — ${WORKFLOW_FILE} concluded success: ${run_url}"
      exit 0
    else
      echo "::error title=Fleet run did not succeed::${WORKFLOW_FILE} concluded '${run_conclusion}': ${run_url}"
      echo "Stopping the chain here — a failed fleet must not silently let a later, cheaper-looking green stand in for it."
      exit 1
    fi
  fi
  elapsed=$((SECONDS - start))
  if [ "$elapsed" -ge "$POLL_BUDGET_S" ]; then
    echo "::error title=Fleet run timed out::${WORKFLOW_FILE} still '${run_status}' after $((POLL_BUDGET_S/60))m: ${run_url}"
    exit 1
  fi
  echo "  ${WORKFLOW_FILE} status=${run_status} (elapsed ${elapsed}s / ${POLL_BUDGET_S}s) — re-checking in 30s..."
  sleep 30
done
