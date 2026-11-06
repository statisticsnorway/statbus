---
id: STATBUS-573
title: >-
  Import warns when a unit's birth date precedes its first valid_from within the
  same year
status: In Progress
assignee: []
created_date: '2026-11-05T16:49:00Z'
updated_date: '2026-11-06T10:02:00Z'
labels:
  - import
  - history
dependencies: []
type: feature
ordinal: 492204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
A statistician reading births for a year sees every unit born in that year, counted in the month it was born, consistent with the stock.

## Zoom out
History counts a birth only when a counted version's existence starts at its birth_date (existence from = GREATEST(valid_from, birth_date), STATBUS-460; births rule C, owner decision 2026-11-05 under STATBUS-558). When data arrives late, a unit born 2026-03-01 is imported with valid_from 2026-05-07: it enters the stock in May as 'added' and is never counted as a birth. Norway 2026: 35 establishments, e.g. 73598, 74463, 74674. The fix belongs at import, not in history.

## Zoom in
The import marks such a row with a warning naming both dates, so the operator can set valid_from to the birth date. History then counts the birth in its month exactly: the delta tables subtract the unit's old contribution and add the new one.

## Closing review
Document the warning in doc/import-system.md. No memory or cleanup expected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An import row whose birth_date is in the current year and earlier than its valid_from gets a warning naming both dates
- [ ] #2 Rows with birth_date before the current year, or birth_date on or after valid_from, get no such warning
- [ ] #3 A regression test committed before the change shows the missing warning
<!-- AC:END -->
