---
id: STATBUS-472
title: >-
  Double the activity category name bound to 512 as the interim workaround
  (multi-language deferred)
status: In Progress
assignee: []
created_date: '2026-10-08 13:12'
updated_date: '2026-10-08 13:12'
labels:
  - sql
  - import
dependencies: []
priority: high
ordinal: 398204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: real classification labels import unedited, and the bound is a deliberate, documented choice with an honest failure above it. The multi-language design, where a custom override carries the local name and the official English name is revealed on demand, is DEFERRED by the owner and recorded in STATBUS-471. Until we support it, a longer field is the pragmatic workaround, and how an operator slices several languages into that field is their business.

WHY THE DOUBLED FIELD IS ENOUGH FOR NOW. activity_category.name is currently character varying(256). Real bilingual labels reach 252 characters in the field file (ClassificationsSBVer2_ActivityCategoris_TCC.csv, 997 rows, path/name, and that copy is already hand-trimmed by the operator to fit), and the longest single-language official label we hold is 136 characters (ISIC4, 766 rows). In PostgreSQL, character varying(n) is a length CHECK, not a storage layout, so doubling it costs nothing in row size or disk. It removes an arbitrary rejection without letting in anything worse than we already tolerate.

WHAT TO DO.
1. Double the bound for activity_category.name to 512, as a new forward migration. Never edit a released migration.
2. Check the activity_category_* views and the upsert functions for dependent varchar(256) casts and handle or record any found.
3. Document the bound where the length policy lives, with the measurement evidence beside it. There is currently NO length-policy document anywhere, so this means creating that place.
4. Keep the honest failure: a value above the new bound must still be reported with the row, the column and the limit.

NOTE FROM THE EARLIER ANALYSIS, so it is not rediscovered: classification CSVs do NOT pass through the import pipeline's length_limits step. The getting-started upload COPYs into activity_category_enabled_custom, so a too-long value surfaces as PostgreSQL's 22001 and that message does not name the column, the line number is only in CONTEXT. Making that message actionable is STATBUS-470's family; do not duplicate it here, but do not assume our own validation reports it either.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 activity_category.name is character varying(512) and a label longer than 256 characters, for example a 300-character bilingual label, is accepted.
- [ ] #2 The field file, or a fixture containing a 300+ character label, imports unedited.
- [ ] #3 The bound and the measurement evidence are documented where the length policy lives, creating that document if none exists.
- [ ] #4 Dependent activity_category_* views and upsert functions are checked for varchar(256) casts, and anything found is handled or explicitly recorded.
- [ ] #5 A test covers the long-label case at the new bound.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The doc/db pairing rides in the SAME commit as the migration, as the pre-commit hook requires.
- [ ] #2 The field file or its fixture is imported and its longest label accepted, with the evidence recorded in the ticket.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner decision 2026-10-08: the multi-language discussion (STATBUS-471) is deferred and put back on the To Do list with its notes intact. The owner's simplest workaround wins for now: allow a longer text and let the operator slice multiple languages however they want. This ticket is that doubled field, nothing more; do not build the override/marker design here.
<!-- SECTION:NOTES:END -->
