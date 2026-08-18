---
id: STATBUS-217
title: >-
  arc-gate-conclusion-blind: the gate accepts a required test job by name alone
  — a skipped job would count as proof
status: To Do
assignee: []
created_date: '2026-08-17 21:46'
updated_date: '2026-08-18 07:43'
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
WHAT THIS PART DOES: the stable-promotion gate does not merely check that a CI run was green — it checks the run actually contains one job per required test scenario. That is the STATBUS-199 doctrine: verify what ran, not what the run claims.

WHAT GOES WRONG: the check only looks for each required job's NAME in the run. It never asks how the job ended. A required job that was present but SKIPPED would count as proof — and because skipped jobs do not turn a run red, the run stays green and the gate passes while a scenario never executed. Found 2026-08-17 by the architect during the STATBUS-215 review; not exploitable today, filed to strengthen the doctrine before it becomes a live defect.

THE DETAIL: WorkflowJobsCompleteAtCommit (cli/internal/release/workflow_check.go:218-225) builds a set of the run's job names and checks each required name for membership. No conclusion field is read. Today this cannot fire: the arc matrix either expands into all its jobs or skips as one placeholder entry whose name matches no required arc — and that name mismatch is exactly how the STATBUS-215 phantom run was caught. The hole opens the moment individual matrix jobs become skippable: a per-scenario condition, a future selector mechanism, or the STATBUS-214 orchestrator rework.

THE FIX: require each required job to be present AND to have concluded success. Failures already redden the whole run, so this only closes the skipped and cancelled cases. The refusal message should distinguish "missing entirely" from "present but did not run." Cost: one extra field in the decode struct. The same helper serves the install-recovery gate's scenario jobs, so both gates strengthen in one change.

WHY THAT HELPS: it closes the last reading under which a test could count without running. The gate then measures execution, not appearance — and stays correct through the planned matrix rework instead of quietly weakening the day jobs become individually skippable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 WorkflowJobsCompleteAtCommit requires each required job name to be present AND concluded success; skipped/cancelled required jobs are reported as not-satisfied
- [ ] #2 The refusal message names which required jobs were present-but-not-successful, distinctly from those missing entirely
- [ ] #3 A Go test covers a run whose required job is present with conclusion skipped — the gate must refuse
- [ ] #4 install-recovery-harness's caller is checked for the same expectation (shared helper, two callers)
<!-- AC:END -->
