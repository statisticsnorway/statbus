---
id: STATBUS-577
title: >-
  Reports progress shows the active rebuild instead of staying Pending until
  completion
status: In Progress
assignee: []
created_date: '2026-11-07T19:56:00Z'
labels:
  - frontend
  - worker
  - progress
dependencies: []
priority: high
type: bug
ordinal: 504204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner observed Norway run B on v2026.11.2-rc.02: Statistical Units shows percentage progress, while Reports remains Pending with ~24000 legal units/enterprises and then disappears. Read-only SQL at 2026-11-07 19:55:43Z returned public.is_deriving_reports active=true, step=statistical_unit_facet_reduce. Trace database phase notifications, SSE delivery and navbar state. Preserve the active benchmark and do not change Norway during import.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A regression reproduces the observed pending-to-active-to-completed reports lifecycle and fails before the fix.
- [ ] #2 The navbar displays the actual active reports step and its available progress, while correctly distinguishing waiting for unit derivation from running reports.
- [ ] #3 Relevant SQL/frontend tests and exact-SHA CI pass; the candidate browser workflow visibly transitions through running reports to completion.
<!-- AC:END -->
