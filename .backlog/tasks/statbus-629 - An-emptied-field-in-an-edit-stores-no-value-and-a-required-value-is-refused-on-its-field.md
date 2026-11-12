---
id: STATBUS-629
title: >-
  An emptied field in an edit stores no value, and a required value is refused
  on its field
status: In Progress
assignee: []
created_date: '2026-11-12T16:17:00Z'
updated_date: '2026-11-12T16:17:00Z'
labels: []
dependencies: []
ordinal: 540204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-12 15:42: go through the legal unit and establishment edit pages one by one and make what we have today work, no redesign.

Walkthrough on units imported for it (LU EDIT PAGES AS 6290000001, EST EDIT PAGES SHOP 6290000002; tmp/edit-pages-unit*.sql) found that emptying a field did not do what the import does with an empty cell:
- contact fields and address lines stored '' instead of NULL ('' also passed contact's rule that one value must be given);
- emptying a birth or death date reported Success and kept the old date;
- emptying a statistical variable stored 0;
- an emptied name reached the database;
- a refused save said 'failed to parse form data'.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Emptying a contact field, address line, birth or death date stores NULL
- [x] #2 Emptying a statistical variable or a name is refused with a message on the field, nothing stored
- [x] #3 A refused save's toast says what to fix
- [x] #4 Every field on both edit pages still saves in the Live frame and in a past frame (2024), changing only that frame
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Commits on master: 52b1e5162 (emptied field stores NULL, required value refused on its field), 493f11c7b (refused save's toast says what to fix).
RED/GREEN: tmp/edit-empty-red.log (7 of 9 failing) -> tmp/edit-empty-green.log; tmp/edit-refusal-red.log -> tmp/edit-refusal-green.log. jest 325, tsc 0, lint 0 errors.
Real app on 3007 (tmp/edit-pages-walk*.mjs):
- before the fix (tmp/edit-pages-walk2.log): phone '' stored, address_part1 '' stored, birth date kept 2020-05-02, Employees stored 0;
- after (tmp/edit-pages-walk2-green.log): phone NULL, address_part1 NULL, birth date NULL, Employees refused 'Enter a number' with 16 kept; empty name refused 'Enter a name'; all-empty contact refused by the database's rule (tmp/edit-pages-walk3.log);
- every field, both pages: 20/20 saves in Live (tmp/edit-pages-after-live.log: only the open row changed) and 20/20 in Frame 2024, each asking first (tmp/edit-pages-after-2024.log: 2025 unchanged); identifiers change and restore 4/4; image upload and delete work.
<!-- SECTION:NOTES:END -->
