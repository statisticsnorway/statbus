#!/usr/bin/env bash
set -euo pipefail

if [ -z "$ORCHESTRATOR_RUN_ID" ]; then
  echo "Direct manual paid-fleet dispatch: orchestrator admission is not applicable."
  exit 0
fi

if ! [[ "$ORCHESTRATOR_RUN_ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error title=Invalid orchestrator provenance::orchestrator-run-id must be a positive integer"
  exit 1
fi

if [ -n "${STATBUS_ADMISSION_PARENT_JSON_FILE:-}" ]; then
  parent="$(cat "$STATBUS_ADMISSION_PARENT_JSON_FILE")"
else
  response_file="$(mktemp)"
  error_file="$(mktemp)"
  trap 'rm -f "$response_file" "$error_file"' EXIT

  set +e
  gh api --include "repos/${GH_REPO}/actions/runs/${ORCHESTRATOR_RUN_ID}" \
    >"$response_file" 2>"$error_file"
  gh_rc=$?
  set -e

  http_status="$(awk 'toupper($1) ~ /^HTTP\// { status=$2 } END { print status }' "$response_file")"
  if [ "$gh_rc" -ne 0 ] || { [ -n "$http_status" ] && [ "$http_status" != "200" ]; }; then
    echo "::error title=Orchestrator lookup failed::gh api exited ${gh_rc}; HTTP status ${http_status:-unavailable} while reading run ${ORCHESTRATOR_RUN_ID}"
    if [ -s "$error_file" ]; then
      echo "gh api stderr:" >&2
      cat "$error_file" >&2
    else
      echo "gh api produced no stderr." >&2
    fi
    if [ -s "$response_file" ]; then
      echo "gh api response:" >&2
      cat "$response_file" >&2
    fi
    exit 1
  fi

  if [ -n "$http_status" ]; then
    parent="$(awk 'body { print } /^\r?$/ { body=1 }' "$response_file")"
  else
    parent="$(cat "$response_file")"
  fi
fi
if ! jq -e \
  --argjson id "$ORCHESTRATOR_RUN_ID" \
  --arg sha "$CANDIDATE_SHA" '
    .id == $id and
    .status == "in_progress" and
    .event == "push" and
    .head_sha == $sha and
    .path == ".github/workflows/release-fleet-orchestrator.yaml" and
    (.html_url | type == "string" and test("^https://[^[:space:]]+$"))
  ' <<<"$parent" >/dev/null; then
  candidate_retry_target="${CANDIDATE_REF:-the candidate tag}"
  echo "::notice title=Admission refused: re-dispatch the orchestrator::run ${ORCHESTRATOR_RUN_ID} is no longer the in-progress tag-push Release Fleet Orchestrator for child SHA ${CANDIDATE_SHA}. This is not a product arc failure. Re-dispatch the Release Fleet Orchestrator for ${candidate_retry_target}; do not re-run this arc child."
  echo "::error title=Stale or invalid orchestrator parent: admission refused before product testing::run ${ORCHESTRATOR_RUN_ID} is not the in-progress tag-push Release Fleet Orchestrator for child SHA ${CANDIDATE_SHA}"
  jq '{id,status,event,head_sha,path,html_url}' <<<"$parent" >&2 || true
  exit 1
fi

if [ "${STATBUS_ADMISSION_TEST_MODE:-}" = "parent" ]; then
  echo "Admitted orchestrator parent: run=${ORCHESTRATOR_RUN_ID} sha=${CANDIDATE_SHA}."
  exit 0
fi

# STATBUS-365 root cause (rc.03 trace, 2026-09-14): this fetch was the line
# that killed rc.01, rc.02 and rc.03. Under `set -e` with `--quiet` it exited
# non-zero without a word, before the newest-tag check below could speak.
# The checkout is a detached tag ref with fetch-depth 0, so the tags this
# check needs are already present; a refresh is worth having but must not
# be able to abort admission. Print git's reason if it fails, then decide on
# the tags we have — exactly what the orchestrator's own joints do.
if ! fetch_err="$(git fetch --tags origin 2>&1)"; then
  echo "::warning title=Tag refresh failed::git fetch --tags origin exited non-zero; deciding on the tags already checked out. git said: ${fetch_err}"
fi
newest="$(git tag --sort=-version:refname | grep -- '-rc\.' | sed -n '1p' || true)"
if [ -z "$newest" ] || [ "$CANDIDATE_REF" != "$newest" ]; then
  echo "::error title=Superseded queued fleet run::candidate ${CANDIDATE_REF} is no longer the newest RC (${newest:-none}); refusing before VM or fixture side effects"
  exit 1
fi
candidate_tag_sha="$(git rev-list -n1 "$CANDIDATE_REF" 2>/dev/null || true)"
if [ "$candidate_tag_sha" != "$CANDIDATE_SHA" ] || [ "$(git rev-parse HEAD)" != "$CANDIDATE_SHA" ]; then
  echo "::error title=Candidate provenance mismatch::tag ${CANDIDATE_REF}, checked-out HEAD, and child SHA must all resolve to ${CANDIDATE_SHA}"
  exit 1
fi

echo "Admitted orchestrated paid run: parent=${ORCHESTRATOR_RUN_ID} candidate=${CANDIDATE_REF} sha=${CANDIDATE_SHA}."
