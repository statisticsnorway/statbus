---
id: STATBUS-472
title: >-
  Double the activity category name bound to 512 as the interim workaround
  (multi-language deferred)
status: In Progress
assignee: []
created_date: '2026-10-08 13:12'
updated_date: '2026-10-08 13:14'
labels:
  - sql
  - import
dependencies: []
priority: high
ordinal: 398204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: real classification labels import unedited, and the bound is a deliberate, documented number with an honest failure above it. Double activity_category.name from character varying(256) to character varying(512). That is the whole change.

WHY. Real bilingual labels reach 252 characters in the field file (ClassificationsSBVer2_ActivityCategoris_TCC.csv, 997 rows, path/name, already hand-trimmed by the operator to fit), while the longest single-language official label we hold is 136 (ISIC4, 766 rows). In PostgreSQL, character varying(n) is a length CHECK, not a storage layout, so doubling it costs nothing in row size or disk. The multi-language design is deferred; a longer text is the interim workaround, and how an operator slices several languages into it is their business. That discussion is preserved in the notes below as history.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 activity_category.name is character varying(512), and a label longer than 256 characters, for example a 300-character bilingual label, is accepted.
- [ ] #2 Dependent activity_category_* views and upsert functions are checked for varchar(256) casts, and anything found is handled or explicitly recorded.
- [ ] #3 The bound and its measurement evidence are documented where the length policy lives, creating that document if none exists.
- [ ] #4 A test covers the long-label case at the new bound.
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
