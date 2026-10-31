---
id: STATBUS-546
title: >-
  Import definition editor: edit an existing definition's mappings (ignore a
  removed column, map an added one)
status: To Do
assignee: []
created_date: '2026-10-30T17:20:00Z'
updated_date: '2026-10-31T11:16:00Z'
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

Known true as of 2026-10-30: (1) Owner decision: no confirm-on-clone step. The fix for a changed file is editing the definition, and 545 keeps the clone/re-upload workaround safe meanwhile. (2) System definitions (custom=false; all 10 on dev) are not editable in the wizard, so the prototype adds 'copy definition' as the way in. (3) Finding: disabling an external_ident_type (tax_ident on the dev copy) makes its file columns ignored too (job 51: tax_ident_raw, legal_unit_tax_ident_raw). The rows then fail at review for lacking an identifier. The editor should surface this, e.g. say which disabled identifier or variable a column belongs to, and offer to enable it rather than only 'Add as ignored'. (4) Branch state: origin/feat/import-definition-editor 71e978b03 is exploration, not for merge. The owner will rebase and preview. Before any merge it needs doc/db and types regen (the commit hook was bypassed on the branch), SQL tests, and a browser check. The owner removed the obsolete branches db-snapshot, feature/pg-oauth (needs psql interactivity, unusable) and feature/mint-prototype, plus the merged fix/ssh-socket-listener; feature/pgadmin stays for STATBUS-173 and db-seed stays because the upgrade refspecs fetch it.

2026-10-31, owner: parked until owner and agent review the screens together and decide whether to take this home. Since rc.03 the ignored-column warning names the disabled variable or identifier type, which covers the lifecycle case. The remaining value is files whose columns don't match a definition. Open design question: copy a built-in definition and edit the copy, or edit in place. Branch origin/feat/import-definition-editor 71e978b03 is the starting point.
<!-- SECTION:NOTES:END -->
