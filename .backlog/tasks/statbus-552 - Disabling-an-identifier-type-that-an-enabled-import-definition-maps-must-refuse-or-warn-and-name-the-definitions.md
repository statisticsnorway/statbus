---
id: STATBUS-552
title: >-
  Disabling an identifier type that an enabled import definition maps must
  refuse, or warn and name the definitions
status: To Do
assignee: []
created_date: '2026-10-30T23:21:00Z'
updated_date: '2026-10-30T23:22:00Z'
labels: []
dependencies: []
type: bug
ordinal: 475204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Since STATBUS-545, a file column that the definition no longer maps is kept as 'ignored'. Disabling an external_ident_type (seen on the dev copy: tax_ident disabled) therefore turns its file columns (tax_ident, legal_unit_tax_ident) into ignored columns silently, and every row then fails at review for lacking an identifier (job 51 statbus_545_reupload on statbus_local). The guard belongs where the identifier type is disabled, not in the import. Independent of the editor in STATBUS-546.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Disabling an external_ident_type that an enabled import definition maps is refused, with an error naming those definitions, unless the caller explicitly confirms
- [ ] #2 The admin UI shows that refusal with the definition names
- [ ] #3 A regression test, extending an existing test, shows that disabling a mapped identifier type is refused without confirmation and succeeds with it
<!-- AC:END -->
