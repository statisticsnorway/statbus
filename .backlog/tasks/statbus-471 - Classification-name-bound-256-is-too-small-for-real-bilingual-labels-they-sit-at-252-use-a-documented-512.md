---
id: STATBUS-471
title: >-
  Classification name bound: 256 is too small for real bilingual labels (they
  sit at 252); use a documented 512
status: In Progress
assignee: []
created_date: '2026-10-08 12:36'
updated_date: '2026-10-08 12:36'
labels:
  - sql
  - import
dependencies: []
priority: high
ordinal: 397204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: real classification labels import unedited. Our declared bound is chosen from evidence and written down, and a value that exceeds it produces a message the operator can act on.

EVIDENCE (measured 2026-10-08). Ville's field file /Users/jhf/Downloads/ClassificationsSBVer2_ActivityCategoris_TCC.csv: 997 data rows, columns path,name, comma-delimited. IMPORTANT: the copy he attached is his TRIMMED version. In it the name column reaches 252 characters (mean 92) while path stays at 5. He reported the untrimmed file failing with 'varchar is set to 256, at least 1 of my lines is too long', and that trimming a few lines made it work, so real bilingual labels sit exactly at the 256 edge and anything slightly longer is rejected outright. For comparison, the longest single-language official label we hold is 136 characters (ISIC4, 766 labels, mean 42); the other classifications are far shorter (SectorCodes 65, LegalForms 62, DataSources 24, Regions 23, our shipped demo 29). The house default is character varying(256) on essentially every name column (activity_category.name, tag.name, establishment.name, legal_unit.name, enterprise_group.name, relative_period names).

THE FACT THAT SETTLES THE 'BLOAT' QUESTION. In PostgreSQL, character varying(n) is a length CHECK, not a storage layout: values are stored as varlena exactly like text. A bound therefore has no effect on row size or disk use. Its only effect is rejecting or truncating values, so a too-small bound buys nothing and costs the field real work, which is what happened here.

RECOMMENDATION: set the classification-name bound to 512 and adopt 512 as the documented bound for name columns generally. That is twice the largest label ever seen in the field (252) and 3.8 times the longest single-language official label (136), while still bounding absurd input. Keep the existing honest import behaviour: when a value exceeds the bound, the message names the row, the column and the limit (acceptance criterion 3 of STATBUS-470).

SCOPE: activity_category.name first, because that is the observed failure, plus the length-limit policy that references the current bound. Not a blanket rewrite of every text column.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A classification label longer than 256 characters, for example a 300-character bilingual label, imports successfully, and activity_category.name enforces the new documented bound.
- [ ] #2 The field file imports unedited: the attached TCC CSV, or an equivalent fixture containing a 300+ character label, is accepted without the operator trimming lines.
- [ ] #3 The bound is 512 for classification names, documented where the length policy lives, with the measurement evidence recorded next to it.
- [ ] #4 A value exceeding the new bound still fails with a message naming the row, the column and the limit.
- [ ] #5 Tests cover the long-label case at the new bound.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The field file, or a fixture derived from it, is imported in a test and its longest label is accepted; the doc/db pairing is regenerated in the same commit as the schema change.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner report 2026-10-08 from Finland: Ville had to trim lines in his ActivityCategories CSV because 'varchar is set to 256, at least 1 of my lines is too long'. The owner asked what the longest string length sensible is; measurement shows real bilingual labels reach 252, so 256 is at the edge of real data, and since varchar(n) is only a check in PostgreSQL there is no storage cost to a larger bound.
<!-- SECTION:NOTES:END -->
