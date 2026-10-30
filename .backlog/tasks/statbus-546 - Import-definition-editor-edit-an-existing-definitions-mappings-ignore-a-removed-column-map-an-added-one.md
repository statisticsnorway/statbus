---
id: STATBUS-546
title: >-
  Import definition editor: edit an existing definition's mappings (ignore a
  removed column, map an added one)
status: To Do
assignee: []
created_date: '2026-10-30T17:20:00Z'
updated_date: '2026-10-30T17:39:00Z'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch rebased onto master and pushed as origin/feat/import-definition-editor (7fa0e160d): 5 editor commits cherry-picked, plus 3 fixups. (1) The migration was renamed to 20261030173648_import_definition_auto_slug so it sorts after released migrations. (2) Header detection is CSV/TSV only, because exceljs and feat/excel-import-export never reached master. (3) The command palette conflict is resolved, with definition items under Import Actions. tsc and eslint pass. Not yet run: the migration against a database, SQL tests, the UI in a browser. Next: check what the wizard already covers against the ACs. It creates new definitions and edits the source columns of existing ones. The gap is marking a column ignored and mapping an added column on an existing definition; then verify against job 50 / dev job 38.
<!-- SECTION:NOTES:END -->
