---
id: STATBUS-573
title: >-
  Import warns when a unit's birth date precedes its first valid_from within the
  same year
status: In Progress
assignee: []
created_date: '2026-11-05T16:49:00Z'
updated_date: '2026-11-06T10:04:00Z'
labels:
  - import
  - history
dependencies: []
type: feature
ordinal: 492204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
History counts a birth only when a counted version's existence starts at its birth_date (existence from = GREATEST(valid_from, birth_date), STATBUS-460; births rule C, owner decision 2026-11-05 under STATBUS-558). Data that arrives late breaks that, so a statistician reading births for a year misses units born that year. The fix belongs at import, where the user can still correct the row.

Example: a unit born 2026-03-01 is imported with valid_from 2026-05-07. It enters the stock in May as added and is never counted as a birth (Norway 2026: 35 establishments, e.g. 73598, 74463, 74674). The import marks the row that starts the unit's timeline with a warning naming both dates, so the operator can set valid_from to the birth date. History then counts the birth in its month: the delta table subtracts the unit's old contribution and adds the new one.

doc/import-system.md describes the warning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An import row whose birth_date is in the current year and earlier than its valid_from gets a warning naming both dates
- [ ] #2 Rows with birth_date before the current year, or birth_date on or after valid_from, get no such warning
- [ ] #3 A regression test committed before the change shows the missing warning
<!-- AC:END -->
