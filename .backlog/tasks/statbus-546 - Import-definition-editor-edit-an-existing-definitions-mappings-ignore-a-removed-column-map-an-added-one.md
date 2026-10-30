---
id: STATBUS-546
title: >-
  Import definition editor: edit an existing definition's mappings (ignore a
  removed column, map an added one)
status: To Do
assignee: []
created_date: '2026-10-30T17:20:00Z'
updated_date: '2026-10-30T17:20:00Z'
labels: []
dependencies: []
type: feature
ordinal: 472204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Continue on local branch feat/import-definition-editor (local only, not on origin; last commit 628d5a631; 7407 commits not on master, so it needs a rebase or restart before it can land). STATBUS-545 keeps the clone/re-upload path working: columns the definition no longer maps are kept as 'ignored' with a warning. The real fix is to edit the definition: mark a removed column ignored on purpose, and map a newly added column.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An admin can mark a source column of an existing definition as ignored
- [ ] #2 An admin can add a mapping for a new source column to an existing definition
- [ ] #3 A clone or re-upload against the edited definition imports without ignored-column warnings
<!-- AC:END -->
