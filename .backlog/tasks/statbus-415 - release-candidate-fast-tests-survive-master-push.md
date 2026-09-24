---
id: STATBUS-415
title: A release candidate's Fast Tests run completes even when master moves on
status: To Do
assignee: []
created_date: '2026-09-24 23:56'
updated_date: '2026-09-24 23:56'
labels:
  - release-bug
  - ci
dependencies: []
priority: high
type: bug
ordinal: 366000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A tagged release candidate retains a conclusive Fast Tests run at its own commit even if another commit is pushed to master while testing is underway. Routine superseded master runs may still be cancelled, but the release gate must never lose the candidate's evidence merely because the branch moved. The implementation may protect the candidate run or automatically redispatch the exact candidate SHA and wait for its outcome.

## Grounded evidence, 2026-09-24

- `.github/workflows/fast-tests.yaml:68-85` triggers on Images completion and groups all non-PR runs under fixed `fast-tests-master` with `cancel-in-progress: true` (STATBUS-364). The workflow's run-name and checkout rationale at `fast-tests.yaml:4-33` identify the actually exercised SHA rather than trusting the workflow_run API head SHA.
- Fast Tests run [36061719069](https://github.com/statisticsnorway/statbus/actions/runs/36061719069) exercised `373d15fc359bf642791256d440e734173b300801`, started 2026-09-24 21:28:39Z, and concluded **cancelled** at 21:40:09Z. Newer Fast Tests run [36062861565](https://github.com/statisticsnorway/statbus/actions/runs/36062861565) for `10f094f2b98c797ae17a805ad8efc82ae3141340` was created at 21:39:31Z. The overlap and fixed cancel group explain the failure mode; a cancelled run does not establish a red test verdict.
- `.github/workflows/fast-tests.yaml:56-61` says stable promotion requires a green run at the release candidate's SHA. `cli/cmd/release/release.go:141-253` consults Fast Tests evidence at the selected commit and distinguishes green, pending, failed, and missing states. A later master run at another SHA cannot replace the candidate's green verdict.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A workflow/orchestrator contract test models a candidate Fast Tests run at commit A followed by a master push and run at commit B. The candidate run at A is not cancelled without a replacement run explicitly dispatched at A; the B run never masquerades as A's verdict.
- [ ] #2 The chosen mechanism preserves the STATBUS-364 bound for routine superseded master and PR checks while giving tagged-candidate runs their own non-conflicting group or a bounded automatic redispatch/wait at the candidate SHA. A manual workaround is not the mechanism.
- [ ] #3 The stable release check waits for and accepts only a green Fast Tests verdict actually exercising the candidate SHA. A genuinely failed candidate run remains red and blocks promotion, and a pending redispatch remains pending rather than green.
- [ ] #4 A real candidate-tag exercise starts Fast Tests, pushes a later master commit while it is in flight, and records the candidate run ID, later run ID, final conclusions, exercised SHAs, and the release gate outcome. The candidate reaches a conclusive green or genuine red result without an operator reconstructing lost evidence.
<!-- AC:END -->
