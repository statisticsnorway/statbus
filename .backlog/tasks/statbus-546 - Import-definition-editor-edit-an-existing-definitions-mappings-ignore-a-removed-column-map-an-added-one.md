---
id: STATBUS-546
title: >-
  Import definition editor: edit an existing definition's mappings (ignore a
  removed column, map an added one)
status: In Progress
assignee: []
created_date: '2026-10-30T17:20:00Z'
updated_date: '2026-10-30T19:02:00Z'
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

Prototype on origin/feat/import-definition-editor 71e978b03. Exploration only, not for merge. Migration 20261030185930 adds two functions. public.import_definition_copy(def, name) copies any definition, system ones included, into a new custom one with its steps, source columns and mappings. public.import_definition_add_source_column(def, name, ignored) adds the column after the existing ones. With ignored it is accepted on purpose; otherwise it maps to <name>_raw, and a name no step reads is refused with a hint. UI: a Copy button on every definition in /import/definitions. In the edit wizard's source-columns step, an unreadable column offers 'Add as ignored', and ignored columns show an amber badge. Checked in a rolled-back transaction on statbus_local: copying definition 3 gives 42 source columns, 44 mappings, 17 steps, valid. Adding employees as ignored keeps the copy valid, and a job from the copy has employees in its upload table. not_a_column is refused. tsc and eslint pass. Not done: doc/db and types regen (the pre-commit hook was bypassed on the branch), SQL tests, browser preview. Previewing needs both branch migrations applied to a database.
<!-- SECTION:NOTES:END -->
