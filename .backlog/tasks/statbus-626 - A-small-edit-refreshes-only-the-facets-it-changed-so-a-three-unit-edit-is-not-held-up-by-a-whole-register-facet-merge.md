---
id: STATBUS-626
title: >-
  A small edit refreshes only the facets it changed, so a three-unit edit is not
  held up by a whole-register facet merge
status: To Do
assignee: []
created_date: '2026-11-12T00:59:00Z'
updated_date: '2026-11-12T01:01:00Z'
labels:
  - performance
  - db
dependencies: []
type: enhancement
ordinal: 537204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A small edit should cost in proportion to the units it changed, not to the size of the register.

Zoom out: after every recalculation the facet reduce rebuilds the whole facet table, whatever changed. It was scoped once and made global again because the scoped delete could not reach every stale row (facet over-count).

Zoom in: worker.statistical_unit_facet_reduce MERGEs all of public.statistical_unit_facet from the whole staging aggregate (scoped in 20260324144548, collapsed to a global MERGE in 20260429233218: the scoped DELETE missed stale rows whose dimension tuple was not in the pre-dirty snapshot). Bench box night 2026-11-11 (rune dump, STATBUS-616 tasks.tsv): a 3-unit edit takes 18-24 s; the real work is about 6 s, statistical_unit_facet_reduce alone 11-16 s, history reduce about 2 s. A scoped reduce must keep the self-healing property: every target row that any dirty slot ever contributed to is reachable.

Closing review: the reason for the scope rule recorded on the procedure; no memory change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After any sequence of edits, deletes and moves, statistical_unit_facet equals a full statistical_unit_facet_derive('-infinity','infinity'), shown by a test that includes the partial-contributor delete that broke the old scoped path
- [ ] #2 A 3-unit edit on the Norway register spends under 3 s in statistical_unit_facet_reduce on the bench box
- [ ] #3 A 50 % change and a full recalculation on the bench box give the same tables as before, with statistical_unit_facet_reduce taking no longer than it does today
<!-- AC:END -->
