---
id: STATBUS-260
title: >-
  chain-push-cannot-trigger: the orchestrator's deploy-branch push uses the
  default token, which GitHub never lets trigger the listening workflow — the
  dev poke dies in the station
status: To Do
assignee: []
created_date: '2026-08-19 20:17'
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
