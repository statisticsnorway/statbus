---
id: STATBUS-217
title: >-
  arc-gate-conclusion-blind: the gate accepts a required test job by name alone
  — a skipped job would count as proof
status: To Do
assignee: []
created_date: '2026-08-17 21:46'
updated_date: '2026-08-18 07:41'
labels:
  - ci
  - release
  - quality-gate
dependencies: []
references:
  - cli/internal/release/workflow_check.go
  - cli/cmd/release.go
priority: low
type: enhancement
ordinal: 217000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the gate verifies what actually ran, not what the run claims (STATBUS-199). Checking that a job merely EXISTS is a weaker test than that doctrine intends.

FOUND: 2026-08-17 by the architect during the STATBUS-215 review. Not exploitable today — filed to strengthen the doctrine before it becomes a live defect.

THE HOLE: the completeness check (cli/internal/release/workflow_check.go:218-225) marks a required arc job as satisfied when a job WITH THAT NAME appears in the run. It never looks at how the job ended. A required job that appeared but was SKIPPED would still count — and because skipped jobs do not turn a run red, the run stays green and the gate passes.

WHY IT CANNOT FIRE TODAY: the arc matrix either expands into all of its jobs or skips as one placeholder entry whose name matches no required arc — and that name mismatch is precisely how the STATBUS-215 phantom run was caught. The hole opens the moment individual matrix jobs become skippable: a per-scenario condition, a future selector mechanism, or the STATBUS-214 orchestrator rework.

THE FIX: require each required job to be present AND to have concluded success. Failures already turn the whole run red, so this only closes the skipped and cancelled cases. The cost is one extra field in the decode struct and a clearer refusal message naming which arcs did not actually run. The same helper serves the install-recovery gate's scenario jobs, so both gates get the fix in one change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 WorkflowJobsCompleteAtCommit requires each required job name to be present AND concluded success; skipped/cancelled required jobs are reported as not-satisfied
- [ ] #2 The refusal message names which required jobs were present-but-not-successful, distinctly from those missing entirely
- [ ] #3 A Go test covers a run whose required job is present with conclusion skipped — the gate must refuse
- [ ] #4 install-recovery-harness's caller is checked for the same expectation (shared helper, two callers)
<!-- AC:END -->
