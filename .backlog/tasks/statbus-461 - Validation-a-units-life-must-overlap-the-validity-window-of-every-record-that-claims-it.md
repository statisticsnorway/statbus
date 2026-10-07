---
id: STATBUS-461
title: >-
  Validation: a unit's life must overlap the validity window of every record
  that claims it
status: To Do
assignee: []
created_date: '2026-10-07 22:35'
updated_date: '2026-10-07 22:35'
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
NORTH STAR: importing a row for a unit whose existence interval does not overlap that row's validity window fails with a clear per-row error instead of silently creating a contradictory unit record. Owner request 2026-10-07, refining the STATBUS-458/460 finding. RULE (overlap, NOT containment): reject a row when birth_date >= valid_until (the unit was born after the record window ends) or death_date <= valid_from (the unit died before the record window starts). Equivalently: COALESCE(birth_date, valid_from) < valid_until AND (death_date IS NULL OR death_date > valid_from). IMPORTANT, must not be over-tightened: birth_date > valid_from is EXPLICITLY ALLOWED and is the intended semantics (the file gives a period window and the birth date says when inside it the unit was born, e.g. valid_from 2024-01-01 with birth_date 2024-11-01). Likewise death_date < valid_until is allowed (a unit may die mid-window). So the check is only about the two ends that make the intersection empty. It is not 'birth and death must be inside valid_from..valid_to'. EVIDENCE (dev, 2026-10-07, read-only): the scan SELECT ... FILTER (birth_date >= valid_until) / (death_date <= valid_from) over statistical_unit returns exactly ONE violating row out of 167: establishment unit_id 17, valid_from 2023-01-01, valid_to 2023-12-31, valid_until 2024-01-01, birth_date 2024-11-01 (born after the record window ends). The same scan shows 14 establishment rows with birth_date > valid_from, which is the allowed case and must keep importing, and zero death-date violations. The single violator is demo fixture data: app/public/demo/formal_establishments_units_with_source_dates_demo.csv row 'Drill Down Norway AS' (valid_from 2023-01-01, valid_to 2023-12-31, birth_date 01.11.2024), the sibling of the 'Drill Up Norway AS' row that starts 2024-01-01 in the same file. WHY THIS EXISTS: the demo file gives every establishment valid_from 2023-01-01, and the same 01.11.2024 birth date was applied to a row whose window ends in 2023, which is contradictory under the existence model in STATBUS-460. WHERE IT BELONGS: statistical_unit currently has NO check constraints at all on its dates (verified on dev: pg_constraint returns no CHECK for the table), and no import step covers date consistency - definition 4 runs steps valid_time, establishment, length_limits and others, so a new check step (or an addition to the validity-period step) is the natural home. Note valid_time is step 1 and length_limits is step 21, so validation steps are an established pattern. Decision to make during implementation: hard error (owner asked for a failing validation) versus warning counted in import_job.warning_count. Recommended: hard error for new imports, because the row is internally contradictory, plus a scan that reports any legacy violators so a released deployment sees the list before the gate is switched on. The shipped demo data must be fixed in the same ticket so a fresh seed still imports cleanly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A validation exists in the import pipeline (a step for the validity-period or a new date-consistency step) that rejects a row where birth_date >= valid_until, with a message naming the row, the unit, the window and the birth date.
- [ ] #2 The same validation rejects a row where death_date <= valid_from.
- [ ] #3 The validation does NOT reject birth_date > valid_from (the intended 'born during the window' case) nor death_date < valid_until: dev has 14 establishment rows of the first kind and a fresh seed must still import them without errors.
- [ ] #4 A pg_regress test covers all three cases: born after the window ends (rejected), died before the window starts (rejected), born inside a later window and died mid-window (accepted), asserting the actual error text for the rejections and the resulting row counts for the accepted case.
- [ ] #5 The shipped demo data is fixed so the seed passes the new validation: app/public/demo/formal_establishments_units_with_source_dates_demo.csv row 'Drill Down Norway AS' (valid_from 2023-01-01, valid_to 2023-12-31, birth_date 01.11.2024) is corrected, and a fresh create-db plus demo import reports zero violations.
- [ ] #6 A scan query is documented in the ticket (filtering statistical_unit and the unit history tables on birth_date >= valid_until OR death_date <= valid_from) so any released deployment can list its existing violators before the gate is enabled.
- [ ] #7 The check applies to every unit type that carries these columns (establishment, legal_unit, enterprise), not just establishments.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The violation count is measured on the largest available dataset (the no dump) and recorded, so we know whether enabling the gate would block a real deployment's next import.
- [ ] #2 doc/data-model.md (or the closest data-model doc) states the rule next to the STATBUS-460 existence rule, since the two are the same semantics seen from two sides.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RELATED: STATBUS-460 is the counting side of the same semantics (count a unit only if its existence interval covers the instant). 461 is the data side (do not accept records whose window cannot overlap the unit's life). File them together in review. Owner asked for 461 directly after approving 460.
<!-- SECTION:NOTES:END -->
