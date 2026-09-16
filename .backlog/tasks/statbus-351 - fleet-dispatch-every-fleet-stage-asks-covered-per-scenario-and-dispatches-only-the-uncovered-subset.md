---
id: STATBUS-351
title: >-
  fleet dispatch: every fleet stage asks `covered` per scenario and dispatches
  only the uncovered subset
status: In Progress
assignee: []
created_date: '2026-09-04 07:18'
updated_date: '2026-09-16 22:34'
labels:
  - release
  - ci
  - cost
dependencies:
  - STATBUS-350
priority: medium
type: task
ordinal: 8
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Purpose

Make every paid fleet dispatch and the stable promotion gate answer the same
per-scenario coverage question from one Go implementation. CI may fail open by
running work when evidence is unreadable, but it must expose that diagnostic as
a red job. Promotion remains fail-closed.

## Completed

- Added `./sb release covered-subset <workflow> <commit>`. It derives the target
  commit's scenario domain, applies `release.DecideCoverage` to every scenario,
  prints only uncovered selectors, returns an empty successful result when all
  are covered, and returns exit 2 without a partial selector list when any
  answer is undecidable.
- Changed the install-recovery and upgrade-arc orchestrator stages to dispatch
  only the uncovered selectors. An undecidable answer dispatches the full suite
  instead of guessing a skip.
- Deleted the duplicate workflow-local bash sensitivity decision.
  `ops/release/upgrade-sensitive-paths.txt` and the Go coverage library are the
  single sensitivity authority for dispatch and promotion.
- Added bounded, classified, visible HTTP retry for genuinely intermittent
  evidence reads. Network failures, timeouts, 5xx, 429, and rate-limited 403s
  retry; deterministic authentication, not-found, and decode failures fail
  immediately.
- Added the independent `coverage-question-health` orchestrator job. It becomes
  red with the exact evidence error when a fleet had to fail open, while the
  fleet dispatch itself continues. It is not in the dispatch dependency chain.
- Kept the stable gate authoritative and fail-closed on unreadable evidence.

## Observed validation

- The real `./sb release covered-subset` command returned empty subsets at the
  fully proven `v2026.09.0-rc.14` commit and full scenario lists at HEAD after
  sensitive release-machinery changes.
- Go unit and workflow-structure tests cover selector output, no-partial-output
  exit 2, classified retry, full-suite fail-open dispatch, the independent red
  health job, and removal of the bash sensitivity algorithm.
- The Go suites and actionlint passed before the implementation was pushed.

## Remaining

Close this ticket after the next batch RC proves the live tag-fired
orchestrator uses the per-scenario subset paths and the diagnostic health job
reports the evidence channel honestly. STATBUS-350 changes the smoke pair to
use the same one-dispatch selector shape and is therefore part of that batch
proof.
<!-- SECTION:DESCRIPTION:END -->

## Observed validation (2026-09-15 18:24)

The rc.10 recovery ladder exercised the per-scenario subset path for real:
after one scenario failed at cloud provisioning, authenticated
`./sb release covered-subset` selected only that scenario, and the parent-only
`gh run rerun 34973239226 --failed` dispatched a fresh child containing only it,
reusing the 12 already-proven scenario marks. Fresh admission and fleet lease
were revalidated, and the parent resumed the dependent arc stage. This is live
confirmation of the subset/coverage path; final close still awaits the batch RC
per the Remaining note.

## Same-tag re-dispatch evidence (2026-09-16)

After rc.15 arc run `35128438594` failed before scenarios, direct child rerun
was correctly refused by admission. The orchestrator re-dispatch
`35141712346` then stopped at dev-canary `35141864469`: the same-tag re-offer
was interpreted as superseded even though it was the deliberate retry path.

Fix `1eccca23e` makes `ops/ci-deploy-status.sh` idempotent when `completed_at`
is already present, while preserving distinct infra/admission classification.
Independent review ACCEPTed it with mutation control. rc.16 must prove the
orchestrator can re-enter the ladder and reach the arc scenarios.
