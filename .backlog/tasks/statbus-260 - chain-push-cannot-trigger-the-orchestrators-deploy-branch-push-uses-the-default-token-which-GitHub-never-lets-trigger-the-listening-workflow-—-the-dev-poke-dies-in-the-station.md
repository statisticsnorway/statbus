---
id: STATBUS-260
title: >-
  chain-push-cannot-trigger: the orchestrator's deploy-branch push uses the
  default token, which GitHub never lets trigger the listening workflow — the
  dev poke dies in the station
status: Done
assignee: []
created_date: '2026-08-19 20:17'
updated_date: '2026-08-19 20:56'
labels:
  - release
  - ci
dependencies: []
priority: high
type: bug
ordinal: 253000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found live on the chain's first real run (v2026.08.0-rc.08, 2026-08-19 20:12 UTC). The dev-canary leg pointed ops/cloud/deploy/dev at the candidate's commit (verified: branch sits at 1aa56cdd7, exactly the rc.08 commit) — and deploy-to-dev.yaml never fired (latest run: July 20). Root cause verified at source: release-fleet-orchestrator.yaml:449-457 does `git push --force origin <sha>:refs/heads/ops/cloud/deploy/dev` authenticated with `GITHUB_TOKEN`, and GitHub's recursion guard means events caused by the default workflow token DO NOT trigger `on: push` workflows. The comment at :457 — "The branch push above IS the trigger" — states the false premise in the code's own voice. The old master-to-dev button worked because a HUMAN pushed the branch.

Consequence on the live run: orchestrator job 3/5's convergence wait polls for dev to reach a commit nobody asked it to install. The wait's failure behaviour (bounded-with-diagnosis vs hang) is being observed as 247 failure-mode evidence.

REPAIR OPTIONS, for the architect's round-3 STATBUS-258 entry (this defect and that redesign are one decision — the transport is the same leg): (a) minimal: the orchestrator triggers the workflow explicitly via `gh workflow run deploy-to-dev.yaml` (workflow_dispatch already exists in its `on:`) — no new credential, the push remains as the record of WHAT to deploy; (b) the round-3 design replaces the relay entirely (general verb over the governed door, per the King's Lego frame); (c) a PAT/deploy-key push — rejected on sight, it deepens the key dependence 253 retires. Interim note: dev can be given rc.08 tonight by manually dispatching deploy-to-dev (its workflow_dispatch door) after the orchestrator's failure mode is captured.

WHAT IS ACHIEVED: the chain's dev leg actually fires when the chain believes it fired, and no comment in the transport asserts a trigger mechanism GitHub does not provide.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-19 20:51
---
**UNITS 2 AND 3 BUILT AND FROZEN.** Chain: build OK, `go test ./...` green, `golangci-lint run ./...` 0 issues, gofmt clean, `bash -n` clean on the action's script, **actionlint clean — zero NEW findings versus HEAD** (compared file-by-file against a HEAD extraction; the one deploy-to-dev finding is the pre-existing SC2088 on the deliberately-unexpanded `~`, shifted by added lines). Files: `.github/workflows/release-fleet-orchestrator.yaml`, `.github/workflows/deploy-to-dev.yaml`, `.github/actions/dispatch-fleet-and-wait/action.yml`, `cli/cmd/workflow_candidate_transport_test.go` (new).

**The chain now DISPATCHES and NAMES the candidate.** The push-as-trigger step is gone; the dev-canary leg calls the shared `dispatch-fleet-and-wait` with `dispatch-inputs: sha=${{ github.sha }}`, and `deploy-to-dev` accepts a `sha` input. Its `push` trigger is KEPT — STATBUS-244's transitional button still writes that branch, and switching it off would break a live caller; what changed is that the push stopped being the chain's transport.

**I VERIFIED THE CORRELATION OBJECTION RATHER THAN ASSUMING IT DISSOLVES.** The comment I deleted warned that the shared action correlates by `--event=workflow_dispatch`, so using it against a PUSH-triggered deploy would start a second run and watch the wrong one. Reading the action: it snapshots matching workflow_dispatch run ids BEFORE dispatching, takes the set difference, and fails loudly on an ambiguous match. The objection was right about the old shape and dissolves in this one — there is no push-triggered run to compete with, because the dispatch IS the trigger.

Using the shared action needed an optional `dispatch-inputs` passthrough. It is additive: every existing caller passes none and is byte-identically unaffected. Two `set -u` hazards handled at the line — both `"${arr[@]}"` and `${#arr[@]}` on an EMPTY array are unbound-variable errors on bash < 4.4, which would have broken exactly the callers this change is meant to leave alone.

**THE GUARD.** The poll now reads `REQUESTED_SHA`; the box's `deployed_commit=` emit exists only to be compared against it, and a mismatch fails the deploy with both commits named. This also removed the old poke-only degradation: that branch existed because the deployed commit was the only commit the step knew, so a missing emit left it with nothing to poll and it exited 0 having verified nothing — a green reporting on no examination at all. The requested commit is known independently of the box, so convergence is now always verified.

**TWO CONSEQUENCES actionlint CAUGHT that review would not have.** The job exported `deployed: steps.deploy.outputs.deployed`, which only the removed push step set — nothing consumed it anywhere in the file, so it is removed rather than re-sourced to keep a line compiling. And the job no longer writes anything in the repository, so `contents: write` drops to `contents: read`; the checkout's `fetch-depth: 0` justification was rewritten too, since full history is now for the decision point's tag walk, not for writing a branch.

**UNIT 3:** the box command stays `apply-latest`, with a marked block at the exact line that must change when STATBUS-259 lands, saying what to replace it with and that nothing else changes — the guard simply stops having anything to catch. The gap is real today and now LOUD.

**FIVE REDs, mutation site asserted:** poll reverting to the box's emit; a mismatch warning instead of failing; the dispatch losing the sha; the guard step deleted; the branch push returning as transport.

**One of my own tests passed for the wrong reason and I caught it.** The guard assertion sliced a window out of the job's concatenated scripts using YAML indentation as the end marker — but a block scalar STRIPS that indentation, so the marker never matched, the window ran to the end of the job, and `exit 1` was satisfied by a DIFFERENT step. It passed while measuring the wrong thing. Now it selects the guard step by name and reads only that script, and the missing-step case fails loudly.
---

author: foreman
created: 2026-08-19 20:56
---
LANDED as 35f02b00d (architect verdict: LAND after one amendment, applied and re-frozen — the two stale architect-attributed comments at deploy-to-dev.yaml :199/:203 that contradicted the new code are corrected, and the deliberate divergence from the six other deploy workflows is stated so nobody consolidates it back). The chain now dispatches deploy-to-dev explicitly with the candidate SHA as input (dispatch-fleet-and-wait gains an additive dispatch-inputs passthrough, existing callers byte-identical); the poll reads the REQUESTED commit; mismatch fails naming both commits; the absent-emit exit-0 degradation is gone. The :457 false-premise comment died with the push-as-trigger mechanism. Companion commit c81f46494 pins the 40-hex identity (input resolves to itself, uppercase refused naming shapes) that the guard's byte-equality and the future allowlist line both rest on. PROOF PENDING: yaml pieces are proven only by the next candidate's run — the run is the oracle; tonight's rc.08 timeout stands as the before-picture. Remaining on this ticket: nothing — the 259-gated verb swap on the box command is tracked in STATBUS-258/259.
---
<!-- COMMENTS:END -->
