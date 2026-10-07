---
id: STATBUS-461
title: >-
  Validation: a unit's life must overlap the validity window of every record
  that claims it
status: To Do
assignee: []
created_date: '2026-10-07 22:35'
updated_date: '2026-10-07 22:43'
labels:
  - app
  - data-model
  - import
dependencies: []
priority: high
ordinal: 388204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: importing a row for a unit whose existence interval cannot overlap that row's validity window fails THAT ROW with a clear error, and the rest of the file still imports. Owner decision 2026-10-07, following STATBUS-458/460: if it has a birth date and it is not yet born, it does not yet exist, it should not be there and it should not be counted.

THE RULE (overlap, NOT containment). Reject the row when either end makes the intersection empty: birth_date >= valid_until (born after the record window ends) or death_date <= valid_from (died before the record window starts). Equivalently COALESCE(birth_date, valid_from) < valid_until AND (death_date IS NULL OR death_date > valid_from). It must NOT be over-tightened: birth_date > valid_from stays legal and is the INTENDED semantics (the file gives a period window and the birth date says when inside it the unit was born, e.g. valid_from 2024-01-01 with birth_date 2024-11-01), and death_date < valid_until stays legal (a unit may die mid-window). dev has 14 establishment rows of the first kind. The check is therefore NOT 'birth and death must lie inside valid_from..valid_to'.

HOW THE IMPORT SYSTEM ACTUALLY DOES THIS (from doc/import-system.md, section 'Error Handling Rule for Analysis Procedures'). Rows live in a per-job _data table: _upload -> prepare (UPSERT on the is_uniquely_identifying source columns) -> analysis steps in priority order -> processing. An analyse_procedure raises a HARD ERROR by merging its keys into the row's errors JSONB, setting state = 'error' and action = 'skip', and always advancing last_completed_priority. The processing phase only touches rows with action = 'use', so the offending ROW is not imported while every other row in the same file is. That is exactly the required behaviour: a hard error fails the specific rows it pertains to, it does not fail the file. Because the UI highlights the offending input, keys in errors MUST be the column_name of a real source_input import_data_column, and when the message concerns several inputs the same message is repeated under each relevant key (doc wording: the error message MUST be repeated under each relevant source_input column name). The natural keys here are birth_date, plus valid_from or valid_to when the window end is what is at fault. warnings is the soft path where the row continues, so it is NOT what we want here. Steps are declared in import_step (code, priority, analyse_procedure, process_procedure) and linked per definition through import_definition_step; definition 4 'Establishments for LU (Source Dates)' runs valid_time (priority 10), external_idents, the establishment core step, and so on, with length_limits (priority 21) as the existing precedent for a step whose whole job is validation. PLACEMENT: the check needs BOTH the derived window (produced by the valid_time step) and the typed birth and death dates (produced by the core unit step), so it must run after both - its own step (suggested code date_consistency) with an analyse_procedure that owns its own error keys and clears only its own keys when the condition no longer applies. It belongs on every definition that imports units with a validity window, both the source_columns and the job_provided kinds, not only definition 4.

WHAT IS BROKEN TODAY (dev, 2026-10-07, read-only). A scan for (birth_date >= valid_until) OR (death_date <= valid_from) over statistical_unit returns exactly ONE violating row out of 167: establishment unit_id 17, valid_from 2023-01-01, valid_to 2023-12-31, valid_until 2024-01-01, birth_date 2024-11-01. It originates in the demo file app/public/demo/formal_establishments_units_with_source_dates_demo.csv as the row 'Drill Down Norway AS'. Its sibling 'Drill Up Norway AS' starts 2024-01-01 in the same file and does NOT violate, because there the birth date falls inside its own window. legal_unit and enterprise have zero violations.

FIXTURES: TWO DIFFERENT THINGS, KEEP THEM SEPARATE (owner instruction, 2026-10-07). (1) TEST FIXTURE - the broken combination is KEPT and becomes a permanent regression test: a pg_regress test imports a file containing BOTH a violating row and valid rows and asserts that the violating row ends with state = 'error' and action = 'skip', carries the expected message under the expected key, and is absent from the target table, while the valid rows in the same file ARE imported. Written first, so the evidence that it failed against the current code (the bad row importing) is recorded, then implemented, then green. (2) SHIPPED DEMO DATA - 'test data' in the owner's sense: the CSVs people actually load to exercise StatBus (app/public/demo/*.csv, loaded by the app's demo bootstrap and by the pg_regress tests). This must be REPAIRED so the seed no longer contradicts the model. Repair decision for unit 17: either give BOTH of its rows a birth date consistent with the 2023 window (the unit exists in 2023, that is what 'Drill Down' means), or drop the 2023 row if the intent was that the unit only starts in 2024. KNOCK-ON to decide explicitly: the first option adds unit 17 to the 2023 existence count, so the STATBUS-458 worked example changes from 11 to 12, and the expected outputs of the demo tests that load this file must be updated deliberately, each change explained in this ticket and not regenerated blindly.

TESTS AND FIXTURES THAT TOUCH THIS FILE. test/sql/309_load_demo_data_with_source_dates.sql, test/sql/310_idempotent_import_source_dates.sql, test/sql/312_partial_update_establishment_with_regular_import.sql and test/sql/314_consecutive_demo_loads.sql all load app/public/demo/formal_establishments_units_with_source_dates_demo.csv and assert counts in test/expected/*.out, so repairing the demo row WILL move some of those expectations. That is expected work here, and is not a reason to weaken the check.

RELEASE SAFETY. Before the gate is switched on for a deployment, run the documented scan against that deployment's database, including the 1.1 GB no dump, so the number of pre-existing violators is known and can be decided before an import hits the new gate.

RELATION TO 460. 460 is the counting side (a unit counts only if its existence interval covers the instant). 461 is the data side (a record whose window cannot overlap the unit's life is not accepted). Same semantics seen from two sides, filed and reviewed together.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The check is implemented as a real import analysis step (own step code in import_step, linked to every definition that imports units with a validity window, both source_columns and job_provided), not as an ad-hoc filter, and it owns its own errors keys and clears only its own keys when the condition no longer applies.
- [ ] #2 A row with birth_date >= valid_until finishes analysis with state = 'error' and action = 'skip', gets an errors entry whose key is a source_input column name (birth_date, plus valid_from or valid_to where the window end is at fault), and the message names the row_id, the unit, the window (valid_from, valid_to, valid_until) and the birth date.
- [ ] #3 A row with death_date <= valid_from is rejected the same way, with a message naming the death date and the window start.
- [ ] #4 A row with birth_date > valid_from is NOT rejected: dev has 14 such establishment rows, and the acceptance run asserts those rows still import and are present in the target table.
- [ ] #5 A row with death_date < valid_until is NOT rejected, asserted in the same test, so the check is provably about the empty intersection and not about containment.
- [ ] #6 The rejection is per row, not per file: the test fixture holds one violating row and at least one valid row, and asserts the violating row is absent from the target table while the valid rows are present and the job still reaches finished with the violating row skipped.
- [ ] #7 The test was written before the implementation, the evidence that it failed against the pre-change code (the violating row importing) is recorded in this ticket, and it passes after the change.
- [ ] #8 The shipped demo CSV is repaired and a fresh create-db plus demo import reports zero violators from the documented scan query; the repair option chosen (birth date corrected on both unit 17 rows, or its 2023 row dropped) and its effect on the displayed numbers are both stated in this ticket.
- [ ] #9 The expected outputs of the demo tests loading that file (309, 310, 312, 314) are updated deliberately, with each change explained in the ticket as a consequence of the fixture repair rather than regenerated blindly.
- [ ] #10 The documented scan query is run and its result recorded for the no dump before the gate is enabled on any released deployment, so pre-existing legacy violators are known up front.
- [ ] #11 The check applies to every unit type carrying these columns (establishment, legal_unit, enterprise), not only establishments.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 doc/import-system.md documents the new step and its error keys, including that a hard error skips exactly the offending rows while the rest of the file imports, and doc/data-model.md states the overlap rule next to the STATBUS-460 existence rule.
- [ ] #2 The violation count is measured on the largest available dataset (the no dump) and recorded, so enabling the gate is known not to block a real deployment's next import.
- [ ] #3 The demo and seed data people use to test StatBus imports cleanly and passes the new check on a fresh install.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RELATED: STATBUS-460 is the counting side of the same semantics (count a unit only if its existence interval covers the instant). 461 is the data side (do not accept records whose window cannot overlap the unit's life). File them together in review. Owner asked for 461 directly after approving 460.
<!-- SECTION:NOTES:END -->
