---
id: STATBUS-193
title: >-
  parked-row-selfheal-leak: resumeNewSb self-heal can complete a PARKED row —
  guard checks state='in_progress' only
status: To Do
assignee: []
created_date: '2026-07-18 13:27'
labels:
  - upgrade
  - recovery
  - install-recovery
dependencies: []
references:
  - cli/internal/upgrade/service.go
priority: medium
ordinal: 194000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a parked row resolves only by a deliberate un-park (./sb install) or displacement by a fix release — never by an automatic path quietly completing it.
> FOUND: 2026-07-18, by the architect during the STATBUS-192 frozen-diff review (out-of-scope observation recorded on STATBUS-192; pre-existing, NOT introduced by the 192 fix).
> STAGE: triage — architect rules disposition, then engineer-or-mechanic build if ruled a change.

THE OBSERVATION: resumeNewSb's self-heal path can complete a PARKED row. Its guard checks state='in_progress' only — and a parked row IS in_progress with recovery_parked_at set, so the guard does not exclude it. This contradicts the deliberate-un-park-only principle in WORDING, though not in the STATBUS-160 doctrine's outcome (the row still ends in a legitimate terminal state).

WHY IT MATTERS: parked rows are skipped by every automatic resume by design (the 135 parked-skip guard genre); an automatic path that can complete one is the lone exception to that invariant. Even if the outcome is benign today, the asymmetry is the kind of wording-vs-behavior gap that misroutes future reasoning about park semantics.

SCOPE NOTE: do not conflate with STATBUS-192's completeInProgressUpgrade path (which carries the parked-skip guard first, correctly). This is resumeNewSb's own guard.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect rules the disposition: add the parked-skip guard to resumeNewSb's self-heal, or bless the current behavior in writing (doc + code comment naming why parked-complete is acceptable here)
- [ ] #2 The ruled outcome is built and its oracle named (structural test or arc leg) — or the bless is recorded on the ticket and in the code
<!-- AC:END -->
