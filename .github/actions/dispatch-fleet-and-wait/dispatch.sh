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
    printf '%s\n' '{"group_members":[]}'
    return 0
  fi
  cat "$err_file" >&2
  rm -f "$err_file"
  return 1
}

# GitHub's documented response is ordered owner-first under group_members.
fleet_members() {
  jq -c '.group_members // [] | to_entries[] |
    {id:.value.run_id, name:.value.run_name, status:.value.status,
     url:.value.run_html_url, position:(.key + 1)}'
}

describe_members() {
  local json=$1
  local rows
  rows="$(fleet_members <<<"$json")"
  [ -n "$rows" ] || { echo "  <empty>"; return; }
  while IFS= read -r row; do
    jq -r '"  position=\(.position) id=\(.id) name=\(.name) status=\(.status) url=\(.url)"' <<<"$row"
  done <<<"$rows"
}

preflight_fleet_group() {
  local json count
  json="$(fleet_group_json)"
  count="$(fleet_members <<<"$json" | grep -c . || true)"
  if [ "$count" -gt 0 ]; then
    echo "::error title=Hetzner VM fleet occupied::refusing to dispatch ${WORKFLOW_FILE}; ordered owner and waiters follow"
    describe_members "$json"
    return 1
  fi
}

postflight_fleet_group() {
  local our_id=$1 json rows our_position our_status owner
  json="$(fleet_group_json)"
  rows="$(fleet_members <<<"$json")"
  our_position="$(jq -r --argjson id "$our_id" 'select(.id == $id) | .position' <<<"$rows" | head -1)"
  [ -n "$our_position" ] || return 0
  our_status="$(jq -r --argjson id "$our_id" 'select(.id == $id) | .status' <<<"$rows" | head -1)"
  [ "$our_status" = pending ] || return 0
  owner="$(jq -c --argjson id "$our_id" --argjson position "$our_position" 'select(.id != $id and .position < $position)' <<<"$rows" | head -1)"
  [ -n "$owner" ] || return 0

  local owner_id owner_url our_url
  owner_id="$(jq -r .id <<<"$owner")"
  owner_url="$(jq -r .url <<<"$owner")"
  our_url="$(jq -r --argjson id "$our_id" 'select(.id == $id) | .url' <<<"$rows" | head -1)"
  echo "Race detected: our run ${our_id} (${our_url}) queued behind owner ${owner_id} (${owner_url})."
  echo "Cancelling only our exact pending run id ${our_id}; the owner is never cancelled."
  gh run cancel "$our_id"
  for _ in $(seq 1 24); do
    read -r status conclusion < <(gh run view "$our_id" --json status,conclusion --jq '"\(.status) \(.conclusion // \"pending\")"')
    if [ "$status" = completed ] && [ "$conclusion" = cancelled ]; then
      echo "::error title=Fleet admission race::cancelled our pending run ${our_id} (${our_url}); owner ${owner_id} (${owner_url}) remains untouched"
      return 1
    fi
    sleep 5
  done
  echo "::error title=Fleet race cleanup failed::run ${our_id} did not reach completed/cancelled; owner ${owner_id} (${owner_url}) was not touched"
  return 1
}

if [ "${STATBUS_DISPATCH_TEST_MODE:-}" = classify ]; then
  is_paid_fleet_workflow "$WORKFLOW_FILE"
  exit $?
fi
if [ "${STATBUS_DISPATCH_TEST_MODE:-}" = preflight ]; then
  preflight_fleet_group
  exit $?
fi
if [ "${STATBUS_DISPATCH_TEST_MODE:-}" = postflight ]; then
  postflight_fleet_group "$RUN_ID"
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

# The preflight is diagnostic, not atomic. Native workflow concurrency closes
# the race. If it queued this orchestrator-created run behind an owner, remove
# only our correlated waiter so it cannot start after this caller has failed.
if is_paid_fleet_workflow "$WORKFLOW_FILE"; then
  postflight_fleet_group "$run_id"
fi

# POLL TO CONCLUSION: never `gh run watch --exit-status` — it has
# returned 0 for a FAILED run in this org's own deploy history
# (CLAUDE.md). Poll status and branch on conclusion explicitly,
# same pattern as deploy-to-dev.yaml's images-ready gate.
start=$SECONDS
while :; do
  read -r run_status run_conclusion < <(gh run view "$run_id" --json status,conclusion --jq '"\(.status) \(.conclusion // "pending")"')
  if [ "$run_status" = "completed" ]; then
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
