---
id: STATBUS-225
title: >-
  fleet-script-x3: three copies of the dispatch-correlate-poll script in one
  file, each holding the same subtle correlation rule
status: Done
assignee:
  - mechanic
created_date: '2026-08-18 09:54'
updated_date: '2026-08-18 15:03'
labels:
  - ci
  - release
dependencies: []
references:
  - .github/workflows/release-fleet-orchestrator.yaml
priority: low
type: chore
ordinal: 225000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: the release fleet orchestrator dispatches three fleets one at a time. Each of its three jobs runs the same inline script: dispatch with retry, correlate the run GitHub refuses to hand back an id for, then poll that run to its conclusion and branch on it explicitly.

WHAT GOES WRONG: the script exists three times in the same file, differing only in a workflow filename and a poll budget. The correlation step in particular encodes a subtle rule about which run is ours, and three copies of a subtle rule drift — a fix applied to one dispatch step and not the others is invisible in review and silently changes only one third of the chain's behaviour.

THE DETAIL: the inline form was a deliberate choice, matching deploy-to-*.yaml's convention that these dispatch/poll loops live at their call site, and the jobs genuinely need no checkout so an external script would cost one for nothing. That reasoning holds across separate files, where each copy has an independent reason to exist. Inside one file, three near-identical ~70-line blocks are one script with three call sites. The pressure is already visible: the STATBUS-214 review's correlation amendment has to be written three times, correctly, or the chain behaves differently depending on which fleet is running.

THE FIX: extract to a local composite action (for example .github/actions/dispatch-fleet-and-wait) taking the workflow file, ref, commit and poll budget, and call it from all three jobs. The cost is one checkout per job — seconds — against removing about 140 duplicated lines and giving the correlation rule a single home.

WHY THAT HELPS: the next change to how a fleet is dispatched, correlated or polled is made once and applies to all three, and a reviewer reads one implementation instead of diffing three blocks against each other to confirm they still agree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The dispatch/correlate/poll logic exists once, called by all three orchestrator jobs with per-fleet parameters
- [ ] #2 Behaviour is unchanged: same retry counts, same correlation rule, same explicit conclusion branching, same per-fleet poll budgets
- [ ] #3 A failed or cancelled fleet run still stops the chain loudly, and the run URL is still surfaced per fleet
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-18 15:00
---
Folded into the in-flight 223+220 unit (same file, release-fleet-orchestrator.yaml), frozen together, no commits.

MECHANISM CHOSEN: a local composite action, `.github/actions/dispatch-fleet-and-wait/action.yml` — the ticket's own suggestion, and this repo already has precedent for the pattern (`.github/actions/extract-db-logs`, STATBUS-163's "one-definition ruling"). Did not reach for YAML anchors: composite-action inputs/outputs give named, typed parameters (workflow-file, ref, commit-sha, poll-budget-s, github-token) instead of string-substitution into a shared block, and this repo's own established convention for "one definition, multiple call sites" is already the composite-action shape, not anchors.

AC#1 (one definition, three call sites): the full ~120-line dispatch/correlate/poll script (snapshot, retry-dispatch, set-difference correlation, poll-to-conclusion) now lives ONLY in the action.yml. Each of the three orchestrator jobs shrank to a `Checkout` step (required so the local action reference `./.github/actions/dispatch-fleet-and-wait` resolves — GitHub reads local composite actions from the job's own checked-out workspace) + one `uses:` step passing its own workflow-file/poll-budget-s. File went from 487 → 320 lines in the workflow + 145 in the new action.yml — net removal in line with the ticket's ~140-line estimate once you account for the new file's own header/comments.

AC#2 (behavior unchanged): the script body is BYTE-IDENTICAL across all three former copies — I extracted the shared block verbatim (retry count, correlation set-difference logic, explicit conclusion branching, error messages) with only the env var SOURCES changing (from hardcoded per-job env: blocks to `${{ inputs.* }}`). Per-fleet parameters (workflow-file, poll-budget-s) pass through as action inputs exactly as they were hardcoded before.

AC#3 (failed/cancelled still stops the chain loudly, run URL surfaced): unchanged — the action's own `::error` lines fire on dispatch failure, ambiguous correlation, run-not-found, non-success conclusion, and timeout, all naming the run URL where known. Each job's `outputs: run_url` still maps through from the action's `run-url` output (nothing in this file currently consumes it downstream, confirmed by grep — kept for observability/future use, same as before).

Also updated the top-of-file RUN CORRELATION paragraph to point at the new action instead of describing inline per-job logic, and added a permissions comment explaining why `contents: read` is now needed at the workflow level (checkout, for the local action reference).

Validated: `ruby -ryaml` clean on both the workflow and the new action.yml; `actionlint` on both exits 0 (zero findings); extracted the action's embedded script to a standalone file and ran `shellcheck` directly (added a shebang for the extraction only, not in the real file) — exits 0, same clean result as when this script lived inline. Full release/workflow-gate Go suite + `TestReleaseGateLayer_TagFiredWorkflows` re-run fresh, all green (untouched by this fold — no trigger/branches changes).
---

author: foreman
created: 2026-08-18 15:03
---
LANDED at a880ad26f: the dispatch/correlate/poll script lives once as the composite action .github/actions/dispatch-fleet-and-wait (precedent: extract-db-logs, the one-definition ruling); each orchestrator job is now Checkout + one uses: call. The architect verified the extraction faithful where it matters — the correlation block's sort discipline, empty-line stripping, and one/many/zero branching all intact, his amendment surviving the move. Done.
---
<!-- COMMENTS:END -->
