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

parent="$(gh api "repos/${GH_REPO}/actions/runs/${ORCHESTRATOR_RUN_ID}")"
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
  echo "::error title=Stale or invalid orchestrator parent::run ${ORCHESTRATOR_RUN_ID} is not the in-progress tag-push Release Fleet Orchestrator for child SHA ${CANDIDATE_SHA}"
  jq '{id,status,event,head_sha,path,html_url}' <<<"$parent" >&2 || true
  exit 1
fi

git fetch --tags --quiet origin
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
