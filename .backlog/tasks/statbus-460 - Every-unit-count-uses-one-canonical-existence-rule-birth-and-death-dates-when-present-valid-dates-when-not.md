---
id: STATBUS-460
title: >-
  Every unit count uses one canonical existence rule (birth and death dates when
  present, valid dates when not)
status: To Do
assignee: []
created_date: '2026-10-07 22:27'
updated_date: '2026-10-07 22:35'
labels:
  - app
  - dashboard
  - data-model
dependencies: []
priority: high
ordinal: 387204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: one documented SQL definition decides whether a unit EXISTS at an instant, and every screen that answers 'how many units exist' uses it. A unit is counted iff COALESCE(birth_date, valid_from) <= instant AND (death_date IS NULL OR death_date > instant) AND valid_until > instant, deduplicated per unit. Owner decision 2026-10-07: 'if it has a birth date and it is not yet born, it does not yet exist. It should not be there and it should not be counted.' Origin: STATBUS-458 on dev, where the dashboard cards at time context 2023 (valid_on 2023-12-31) show 24 establishments while the Reports Units-over-time chart shows 11. Both are correct answers to different questions. The cards count RECORDS whose validity window covers the instant (unit_type = X AND valid_from <= instant AND valid_to >= instant); the chart uses the existence rule above (statistical_history_def, stock_at_end_of_curr) and therefore excludes units not yet born. The 13-unit gap is exactly the establishments whose record says valid_from 2023-01-01 (valid_to infinity) while birth_date is 2024-11-01 - the demo data rows named Statistics Denmark/Finland/Sweeden, LocalTrade, Statistics Ethiopia, Erdenes Tavan Tolgoi JSC, Oyu Tolgoi LLC, Rainbow shopping, Amman RIAD 13-14, Statbus Norway O/K, MANUAL Auto Uzbekistan, Local Office Picture, plus Drill Down/Up Norway AS. EVIDENCE THAT THIS IS NOT A LOAD-SEQUENCE ARTEFACT (owner asked): dev import tables show ONE file, ONE batch. Job 34 (definition 4, Establishments for LU, Source Dates) created 2026-10-01 09:33:41 with 26 rows, all at batch_seq = 1; job 33 (Legal Units, Source Dates) ran 19 seconds earlier and carries a yearly series (valid_from_raw 2022-01-01: 2 rows, 2023-01-01: 25, 2024-01-01: 25, 2025-01-01: 24). Job 34's rows match the committed demo file app/public/demo/formal_establishments_units_with_source_dates_demo.csv exactly: 26 data rows, every one with valid_from 2023-01-01 and valid_to infinity, 15 of them with birth_date 01.11.2024. So the file itself pairs a 2023 snapshot window with a November 2024 birth date; nothing was loaded for 2023 and later re-loaded for 2024. Unit 17 (Drill Down Norway AS / Drill Up Norway AS) carries both rows in that same file: 2023-01-01..2023-12-31 and 2024-01-01..infinity, both with birth_date 01.11.2024, which is exactly the intended semantics that a record window may be narrower than the unit's life. Related smell: legal_units_demo.csv carries birth_date 01.11.1924 for the same kind of rows, so these 01.11.YYYY values look like generated demo placeholders rather than real founding dates. COVERAGE GAP: no test in test/sql sets a birth_date in 2024 or 2025 at all, so the case 'record window in year N, born in year N+1' is untested, which matches the owner's recollection that we do not test it. SCOPE: the same record-validity predicate is used app-wide - StatisticalUnitCountCard, the two missing-* data-quality cards, atoms/search.ts (the Statistical Units list) and statistical-unit-details/requests.ts (unit detail pages) - so this is a convention change, not a one-card fix.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One canonical SQL definition of 'unit exists at instant d' is documented in the repo and implemented once (for example public.statistical_unit_exists_(unit_type, instant) or an equivalent view), using COALESCE(birth_date, valid_from) <= d, (death_date IS NULL OR death_date > d) and valid_until > d, deduplicated per unit.
- [ ] #2 The dashboard cards (Establishments, Legal Units, Enterprises) use that definition: on dev at 2023-12-31 they show 11 / 23 / 23 and at 2024-12-31 they show 24 / 23 / 23, matching the Reports chart bar for bar.
- [ ] #3 The Statistical Units list and the unit detail pages use the same rule, so a unit born after the selected context instant is not listed for that context.
- [ ] #4 The two data-quality cards that share the old record-validity predicate are either switched to the same rule or explicitly documented as deliberately counting records rather than existing units.
- [ ] #5 A pg_regress test covers a unit whose record window is valid_from 2023-01-01 with valid_to infinity and birth_date 2024-11-01: absent from the 2023 count, present in the 2024 count. A second case covers birth_date inside its own window (valid_from 2024-01-01, birth_date 2024-11-01) and IS counted for 2024.
- [ ] #6 Two tests prove a birth date can no longer leak into an earlier period: (1) the case above with a later year, (2) a death date in the window (existence ends, the unit is gone from later counts even though the record still covers the instant).
- [ ] #7 The estimated-vs-exact flapping is resolved: the card no longer shows a count that can disagree with the chart in kind, and any remaining estimate uses the same predicate.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Measured on the largest available dataset (the no dump) that the existence predicate is fast enough for the dashboard, with the timing recorded in the ticket.
- [ ] #2 doc/data-model.md (or the closest data-model doc) names the canonical existence rule and lists the screens that use it.
- [ ] #3 The 458 example rows are used as the worked example in the test, so the regression is traceable to this ticket.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
APPROVED BY OWNER 2026-10-07 ('sensible to do'). Companion ticket STATBUS-461 adds the import-side gate that keeps data consistent with this rule (a unit's life must overlap each record's window). Sequencing note: this ticket's DoD wants a timing measurement on the largest dataset, and a worker is currently restoring the no dump locally for the STATBUS-421 measurement, so the local timing run comes after that finishes.
<!-- SECTION:NOTES:END -->
