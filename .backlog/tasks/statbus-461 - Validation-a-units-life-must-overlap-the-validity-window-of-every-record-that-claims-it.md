---
id: STATBUS-461
title: >-
  Validation: a unit's life must overlap the validity window of every record
  that claims it
status: To Do
assignee: []
created_date: '2026-10-07 22:35'
updated_date: '2026-10-07 22:47'
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

HOW THE IMPORT SYSTEM ACTUALLY DOES THIS (doc/import-system.md, section 'Error Handling Rule for Analysis Procedures'). Rows live in a per-job _data table: _upload -> prepare (UPSERT on the is_uniquely_identifying source columns) -> analysis steps in priority order -> processing. An analyse_procedure raises a HARD ERROR by merging its keys into the row's errors JSONB, setting state = 'error' and action = 'skip', and always advancing last_completed_priority. The processing phase only touches rows with action = 'use', so the offending ROW is not imported while every other row in the same file is. That is exactly the required behaviour: a hard error fails the specific rows it pertains to, it does not fail the file. Keys in errors MUST be the column_name of a real source_input import_data_column, and when the message concerns several inputs the same message is repeated under each relevant key (doc wording: the error message MUST be repeated under each relevant source_input column name). warnings is the soft path where the row continues, so it is NOT what we want here. Steps are declared in import_step (code, priority, analyse_procedure, process_procedure) and linked per definition through import_definition_step; definition 4 'Establishments for LU (Source Dates)' runs valid_time (priority 10), external_idents, the establishment core step, and so on, with length_limits (priority 21) as the existing precedent for a step whose whole job is validation. PLACEMENT: the check needs BOTH the derived window (produced by the valid_time step) and the typed birth and death dates (produced by the core unit step), so it must run after both - its own step (suggested code date_consistency) with an analyse_procedure that owns its own error keys and clears only its own keys when the condition no longer applies. It belongs on every definition that imports units with a validity window, both the source_columns and the job_provided kinds, not only definition 4.

WHY NOT JUST A CHECK CONSTRAINT. A CHECK on statistical_unit was considered and rejected as the primary mechanism: statistical_unit currently has no CHECK constraints at all on its dates, a constraint would abort the whole statement (and therefore the whole batch) instead of failing the one row, and it cannot express a friendly UI message. Use the import analysis step as the gate; a constraint can be revisited later as a backstop once the fleet is known clean.

WHAT IS BROKEN TODAY (dev, 2026-10-07, read-only). A scan for (birth_date >= valid_until) OR (death_date <= valid_from) over statistical_unit returns exactly ONE violating row out of 167: establishment unit_id 17, valid_from 2023-01-01, valid_to 2023-12-31, valid_until 2024-01-01, birth_date 2024-11-01. It originates in the demo file app/public/demo/formal_establishments_units_with_source_dates_demo.csv as the row 'Drill Down Norway AS'. Its sibling 'Drill Up Norway AS' starts 2024-01-01 in the same file and does NOT violate, because there the birth date falls inside its own window. legal_unit and enterprise have zero violations.

VARIATION MATRIX TO COVER IN THE TEST (owner, 2026-10-07: cover the variations, not only the one row the fixture happens to contain). For a row with window [valid_from, valid_until) built from source dates:
 1. birth_date > valid_until  -> REJECT (born after the window ends)
 2. birth_date = valid_until  -> REJECT (boundary: the window's end is exclusive)
 3. death_date < valid_from   -> REJECT (died before the window starts)
 4. death_date = valid_from   -> REJECT (boundary)
 5. both a birth after the end and a death before the start -> REJECT, with both keys present in errors
 6. birth_date > valid_from   -> ACCEPT (born during the window: the intended case, 14 rows on dev)
 7. birth_date = valid_from   -> ACCEPT
 8. death_date < valid_until  -> ACCEPT (dies mid-window)
 9. death_date = valid_until  -> ACCEPT
10. birth_date only            -> ACCEPT when consistent, REJECT when after the end
11. death_date only            -> ACCEPT when consistent, REJECT when before the start
12. neither date              -> ACCEPT (window alone decides)
13. open-ended window (valid_to = infinity) with a birth date in a LATER year -> ACCEPT. This is the STATBUS-458 business case and it must keep importing: valid_from 2023-01-01, valid_to infinity, birth_date 2024-11-01.
14. a second row for the SAME unit (founding_row_id group) where one row violates and the other is valid -> the violating row is skipped, the valid row is still imported, and the job still finishes. Test both orders (violating row first, violating row second), because the group's first row drives the temporal_merge INSERT.
15. valid_from >= valid_to (an empty or inverted window) with any birth/death date -> the existing invalid_period_source behaviour from the valid_time step must not regress; assert the existing message still wins or is preserved alongside.

STANDARD TEST PRACTICES FOR THIS KIND OF CHECK (follow these exactly).
 * Write the test FIRST and record the evidence that it failed against the current code (today the violating row imports), then implement, then show it green. Put the before/after evidence in the ticket.
 * Assert on the job's own data table (import_job_<id>_data): the row's state = 'error', action = 'skip', and the exact errors JSONB, key for key, message for message. Assert the exact message text, not a substring, so a rewording is a deliberate test change.
 * Assert the ABSENCE of the row in the target table (statistical_unit for the unit_type under test) and the PRESENCE of the valid rows, with row counts, not just 'no error'.
 * Assert the job reaches 'finished' (a hard row error must not fail the job) and that the skipped row is visible in the job's row-state counts.
 * Keep the fixture file self-contained: one file holding the violating rows AND the valid rows, so the accept/reject contrast is provable in a single import. Name the file after the ticket (for example test/data/461_date_consistency_*.csv) so the association is obvious.
 * Do not weaken an existing test to make the new check pass; if a shipped fixture violates the rule, repair the fixture (see below) instead.

UI FRIENDLINESS AND VISIBILITY (required, not optional). The error keys must be real source_input column names so that the existing error UI renders a meaningful field label: app/src/components/import/ErrorDisplay.tsx (ErrorDisplay and ErrorBadges strip a trailing _raw from the key and show it as the field name) and the job data page app/src/app/import/jobs/[jobSlug]/data/page.tsx (which renders the errors column per row, has QUALITY_FILTER_IDS = state, errors, warnings, and counts rows without errors for the ok filter). Requirements: the message is human-readable and names the dates and the unit (for example 'Establishment 17 was born 2024-11-01, after its record window ends 2024-01-01'), carries no SQL statement text or stack trace, is attributable to the birth_date key and to valid_from or valid_to where the window end is the problem, and the row must be filterable as errored in the job data page. If a key is added that is not a source_input column, the UI shows a meaningless badge, so do not do that.

FIXTURES: TWO DIFFERENT THINGS, KEEP THEM SEPARATE (owner instruction, 2026-10-07). (1) TEST FIXTURE - the broken combination is KEPT and becomes a permanent regression test: a pg_regress test imports a file containing BOTH violating rows and valid rows across the variation matrix above and asserts the outcomes. Written first, so the evidence that it failed against the current code is recorded, then implemented, then green. (2) SHIPPED DEMO DATA - 'test data' in the owner's sense: the CSVs people actually load to exercise StatBus (app/public/demo/*.csv, loaded by the app's demo bootstrap and by the pg_regress tests). This must be REPAIRED so the seed no longer contradicts the model. Repair decision for unit 17: either give BOTH of its rows a birth date consistent with the 2023 window (the unit exists in 2023, that is what 'Drill Down' means), or drop the 2023 row if the intent was that the unit only starts in 2024. KNOCK-ON to decide explicitly: the first option adds unit 17 to the 2023 existence count, so the STATBUS-458 worked example changes from 11 to 12, and the expected outputs of the demo tests that load this file must be updated deliberately, each change explained in this ticket and not regenerated blindly. OWNER INPUT REQUESTED on which repair.

TESTS AND FIXTURES THAT TOUCH THIS FILE. test/sql/309_load_demo_data_with_source_dates.sql, test/sql/310_idempotent_import_source_dates.sql, test/sql/312_partial_update_establishment_with_regular_import.sql and test/sql/314_consecutive_demo_loads.sql all load app/public/demo/formal_establishments_units_with_source_dates_demo.csv and assert counts in test/expected/*.out, so repairing the demo row WILL move some of those expectations. That is expected work here, and is not a reason to weaken the check.

RELEASE SAFETY. Before the gate is switched on for a deployment, run the documented scan against that deployment's database, including the 1.1 GB no dump, so the number of pre-existing violators is known and can be decided before an import hits the new gate. If the fleet has violators, the options are: fix the source data, repair the rows forward with a migration, or enable the gate as a warning first. Record the measured number for each deployment checked.

SELF-CONTAINMENT (everything a delegated agent or a later reader needs; no outside context required).
 * Spec and rule: this description. Mechanism: doc/import-system.md, sections 'Error Handling Rule for Analysis Procedures' and 'Defining a New Import Type'.
 * Key tables: import_step (code, priority, analyse_procedure, process_procedure), import_definition_step (definition_id, step_id), import_data_column (column_name, purpose, column_type, step_id), import_definition (slug, valid_time_from, mode, strategy), import_job (definition_id, state, error_count, warning_count), and the per-job import_job_<id>_data and import_job_<id>_upload tables.
 * The columns that already exist for this check: valid_from, valid_to (source_input, valid_time step), derived_valid_from, derived_valid_after, derived_valid_to (internal, valid_time step), birth_date, death_date (source_input, core unit step), typed birth/death internal columns produced by the core step, plus errors, warnings, state, action, last_completed_priority (metadata).
 * Implementation shape: one new import_step row (suggested code date_consistency) plus its analyse_procedure in a migration, added to import_definition_step for every definition that imports units with a validity window. No process_procedure. The procedure must filter its batch, merge its own errors keys, set state='error' and action='skip' only for violating rows, and always advance last_completed_priority for every row in the batch.
 * Existing precedent to copy for style: the length_limits step (code length_limits, priority 21) and the valid_time step (priority 10). The import definitions live in the database; find them with: SELECT id, slug, valid_time_from FROM import_definition ORDER BY id.
 * Commands: ./dev.sh test <number>_<name> to run one pg_regress test; ./dev.sh test fast for the quick set; ./dev.sh recreate-database then load the demo to prove a fresh seed is clean; ./sb psql for interactive checks. Read-only scans on a live deployment: ssh statbus_<slot> 'cd statbus && ./sb psql'.
 * Verification evidence to leave in the ticket: the failing-then-passing test output, the exact errors JSONB observed, the row counts in statistical_unit, the fresh-seed violation count from the scan, and the no-dump violation count.
 * Out of scope here: the counting-side change (STATBUS-460), and any app code change beyond confirming the error renders (the UI already handles an errors JSONB keyed by source_input column names).

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
- [ ] #12 The test covers the full variation matrix, each with its expected outcome asserted: born after the window ends, born exactly on valid_until (reject), died before the window starts, died exactly on valid_from (reject), both violations at once (both keys in errors), born during the window, born exactly on valid_from, died mid-window, died exactly on valid_until, birth only, death only, neither date, open-ended window with a birth in a later year, and a same-unit row pair where one row violates and the other is valid (tested in both orders).
- [ ] #13 The error message is human-readable, names the dates and the unit, contains no SQL statement text or stack trace, and renders in the existing error UI: app/src/components/import/ErrorDisplay.tsx shows the key as a field label (ErrorDisplay and ErrorBadges) and the row is filterable as errored in app/src/app/import/jobs/[jobSlug]/data/page.tsx, evidenced by a screenshot or an explicit statement of what was rendered.
- [ ] #14 The test fixture is a checked-in file named for this ticket (for example test/data/461_date_consistency_*.csv) that holds the violating rows AND the valid rows together, so one import proves both the rejection and the acceptance.
- [ ] #15 For a same-unit row pair, the valid row is still imported when the violating row is skipped, in both orders, and the job reaches finished with the skipped row visible in the job's row-state counts.
- [ ] #16 The ticket carries the before/after evidence: the exact errors JSONB observed, the row counts in statistical_unit, the test output showing it failing before the implementation and passing after, the fresh-seed violation count, and the no dump violation count.
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
