---
id: STATBUS-580
title: >-
  Import warns when a unit's birth date precedes its first valid_from within the
  same year
status: In Progress
assignee: []
created_date: '2026-11-05T16:49:00Z'
updated_date: '2026-11-06T15:44:00Z'
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
- [x] #1 An import row whose birth_date is earlier than its valid_from in the same calendar year, and that starts its unit's timeline, gets a warning under birth_date_raw naming both dates and the month history counts it in; the row still imports
- [x] #2 Rows with birth_date in an earlier year, birth_date on or after valid_from, no birth_date, or that are a later piece of the unit's timeline (in the file or already stored) get no such warning
- [x] #3 Test 369 asserts the warned and unwarned rows of legal units and informal establishments, and fails on the code without the warning
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-05 23:49 owner: each row failing the test warns, except later pieces of the same unit's timeline in the file. Rule implemented: birth_date < valid_from, same calendar year (of valid_from), and the row starts the unit's timeline (no earlier row with the same founding_row_id, no stored version starting earlier). Done in the legal_unit and establishment analyse steps (priority 20), which already resolve birth_date and own the birth_date_raw warning key. Branch statbus-573-birth-before-valid-from (local).

2026-11-06 00:12 Done on branch statbus-573-birth-before-valid-from (local): test 64723126f, fix 4d64f6c3d (migration 20261106000006, doc/import-system.md, doc/db). Test 369: pre-fix no row warned (tmp/573/369-prefix.out); post-fix W01, W05 first piece, W06 first piece (listed second in the file), W10, E01 warned; W02 (earlier year), W03 (on valid_from), W04 (after), W07 (no date), W08 (exists from birth), the later pieces and every row of the second file not warned; all rows import. History B3: W10 corrected in the second file counts as born in March. Fast suite 123/123 after accepting 324 (enterprise ids follow heap order, explained in commit).

2026-11-06 09:56 Rebased onto statbus-558-history-delta 20232ff52 (commits now ad9092de0 test, 2e2d5d9f3 fix). Test 324 no longer prints allocated enterprise ids (558 commit 20232ff52, independent review finding 12), so this branch no longer changes 324; the earlier note's commit ids and 324 acceptance are superseded.

2026-11-06 10:03 Back to In Progress (owner): implemented and tested on the local branch, but not yet reviewed with the owner, landed or pushed. Done after landing, push and CI.

2026-11-06 11:52 Landed in local master 67488988e (fast-forward, owner 11:41: land the whole set, then one release with one full recalculation). Not pushed. Fast suite on that tip 124/124 (tmp/test-stack-fast.log).

2026-11-06 14:06 Renumbered from local STATBUS-573: origin already has a different STATBUS-573 (setup SSH key retry, rabbit's swarm). Ids agreed with rabbit: this is 580, the unit refresh speed ticket is 581, rabbit uses 575-579. Earlier notes and commit messages on local master say STATBUS-573 for this ticket; test 369, its fixtures and the migration comments now say 580.

2026-11-06 15:44 Owner review: the warning belongs on valid_from (the birth date is the fact, valid_from is the field to correct), with the consequence in its explanation. Owner approved the wording: 'After the birth date D in the same year. If the unit existed from birth, set valid_from to D. Why: history counts the unit as added in <Month YYYY>, not as born, so it is missing from the births of <YYYY>.' Test ad531bb3b (369 expects valid_from_raw; on the previous migration all 5 warnings were under birth_date_raw), change 70bbb9de4. Fast suite 124/124 (tmp/test-580-valid-from-fast.log).
<!-- SECTION:NOTES:END -->
