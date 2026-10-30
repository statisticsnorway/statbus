---
id: STATBUS-217
title: >-
  arc-gate-conclusion-blind: the gate accepts a required test job by name alone
  — a skipped job would count as proof
status: Done
assignee: []
created_date: '2026-08-17 21:46'
updated_date: '2026-08-18 08:29'
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
- [x] #1 WorkflowJobsCompleteAtCommit requires each required job name to be present AND concluded success; skipped/cancelled required jobs are reported as not-satisfied
- [x] #2 The refusal message names which required jobs were present-but-not-successful, distinctly from those missing entirely
- [x] #3 A Go test covers a run whose required job is present with conclusion skipped — the gate must refuse
- [x] #4 install-recovery-harness's caller is checked for the same expectation (shared helper, two callers)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-18 08:23
---
**Implemented, frozen for review (no commit).** Files: `cli/internal/release/workflow_check.go`, `cli/cmd/release.go`, `cli/internal/release/workflow_check_test.go`, new `cli/cmd/release_arc_domain_gate_test.go`.

**AC#1 — presence is no longer proof.** `WorkflowJobsCompleteAtCommit` decodes `conclusion` alongside `name` and requires each required job to be present AND concluded `success`. Return shape is a typed verdict instead of the old `(bool, []string, error)`, so the two refusal reasons cannot be conflated:
```go
type UnsuccessfulJob struct { Name, Conclusion string }
type JobsCompleteness struct {
    Complete     bool
    Missing      []string          // never in the run
    Unsuccessful []UnsuccessfulJob // present, no green
}
```
Clean break — all three call sites updated in the same change, no compatibility wrapper.

One judgment call inside the loop: a job NAME can appear more than once in the API's answer (a re-run attempt). Any success for the name counts as proof — the same any-green reading `CheckWorkflowAtCommit` already applies at run level; the first conclusion is what gets reported when none succeeded. Pinned by the `rerun-any-success` arm.

**AC#2 — buckets print apart, because the remedies differ.** New `printJobsCompletenessRefusal` (release.go, next to the seam vars) is shared by both gates:
```
MISSING (never in the run): <job>
DID NOT RUN (present, no green): <job> (conclusion: skipped)
```
A null conclusion renders as `none — the job never ran to completion` rather than an empty parenthesis (`UnsuccessfulJob.String`).

**AC#3 — covered twice, and verified RED.** Helper level: arms `skipped-required-job`, `cancelled-required-job`, `null-conclusion`, each fed through the real JSON decode path (`conclusion: null` sent as actual null, not a pre-emptied string). Gate level: `TestUpgradeArcHarnessGate_SkippedArcJobRefuses` — green run, one required arc, present with conclusion `skipped` → gate returns false and the output names it as present-but-not-run. With the conclusion check neutered, the three helper arms fail with `Complete: got true, want false`.

**AC#4 — checked the second caller, both messages re-read.** `checkInstallRecoveryHarnessGate` (release.go:1478–1505 region) and `checkUpgradeArcHarnessGate` (≈1562–1585) both consume the new verdict; the ride-walk candidate check (≈1671–1690) does too — a prior RC whose arc jobs were skipped is no longer a valid full-suite anchor to ride. Both printed messages were rewritten, not just re-plumbed: the old "job set is INCOMPLETE (missing N/M)" undercounted once skipped jobs exist, so it now reads "N/M required scenario jobs are not proof — a subset or skipped run cannot satisfy this gate", and the success lines say "ran and succeeded" rather than "present". `TestInstallRecoveryHarnessGate_MissingAndSkippedReportedApart` pins the two labels on the install-recovery side.

**Verification:** `go test ./...` in cli/ — 12 packages ok, 0 failures. `golangci-lint run ./...` at 2.12.2 (the CI version) — 0 issues.
---

author: architect
created: 2026-08-18 08:26
---
REVIEW VERDICT — APPROVED, no re-freeze. And the flagged behaviour change is BLESSED — reasoning below, so it is on the record rather than resting on my word.

THE CORE CHANGE IS RIGHT AND WELL-SHAPED. `JobsCompleteness` splitting Missing from Unsuccessful is better than the boolean-plus-list it replaces: the two buckets have genuinely different operator remedies, and the refusal now says which one you are in (AC#2). `UnsuccessfulJob` carrying the raw conclusion string, with String() rendering "none — the job never ran to completion" for a null, means the operator reads WHY a present job did not count instead of inferring it. Both callers of the shared helper strengthen in one change (AC#4). Verified `go test ./cmd/ ./internal/release/ -count=1` passes independently here (exit 0).

BLESSED — THE WALK SEMANTICS CHANGE (foreman's point 2). An RC whose arc jobs were present-but-skipped is no longer a valid full-suite RIDE anchor. Three reasons this is correct, not merely conservative:
1. It is what the ticket was filed to do. An anchor is inherited PROOF. A run whose arc jobs skipped never executed those arcs, so there was never anything to inherit — accepting it was the bug, not a feature being removed.
2. No reachable regression. run-arc's `if:` is job-level, so the matrix either expands wholesale or skips as ONE unexpanded `${{ matrix.scenario }}` entry whose name matches no arc — which lands in Missing and was already disqualifying. So no historical anchor flips verdict under the new reading. I checked the RIDE run shape specifically: its required arcs are all Missing, not Unsuccessful, so RIDE runs were never anchors and still are not.
3. The failure direction is safe. A lost anchor costs one more full-suite run; a wrongly-kept anchor promotes on nothing.

APPROVED — THE RERUN READING (foreman's point 3). Any success for a repeated job name counts, mirroring CheckWorkflowAtCommit's documented any-green semantics; consistency between the run-level and job-level readings is worth more here than a stricter rule, and the divergence would be surprising. Two notes for the record, neither needing action: `runs/{id}/jobs` returns the latest attempt by default, so duplicates are rare in practice; and when nothing succeeded the reported conclusion is `conclusions[0]`, the first the API returned — documented in the code, and only ever a cosmetic choice since the verdict is already "not proof".

ONE CORRECTNESS CHECK I RAN THAT NOBODY FLAGGED: a job with a null conclusion (queued/in-progress) decodes to "" and counts as Unsuccessful — which is right, an unfinished job is not proof. It is also unreachable in practice, since the gate only calls this after CheckWorkflowAtCommit returned Green and a green run has no unfinished jobs. Handled anyway, correctly.
---

author: foreman
created: 2026-08-18 08:29
---
LANDED at d02550da5 as one unit with 216 and 218, architect-approved. All four ACs closed: completeness is conclusion-aware with Missing printed apart from present-but-did-not-run; the skipped-required-job refusal is test-pinned; both callers rewritten. Architect additionally BLESSED the semantics change: a run whose arc jobs skipped is no longer a valid RIDE anchor — an anchor is inherited proof, and a skipped run never executed anything to inherit. Done.
---
<!-- COMMENTS:END -->
