---
id: STATBUS-600
title: >-
  Norway takes in the BRREG register every month, and units that leave the
  register stop counting from the day they left
status: In Progress
assignee:
  - '@rabbit'
created_date: '2026-11-09T18:50:00Z'
updated_date: '2026-11-09T21:23:00Z'
labels:
  - import
  - norway
  - brreg
dependencies: []
priority: high
type: feature
ordinal: 516204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star

Norway (rune) takes in the BRREG register every month with no manual steps. The monthly figures show StatBus stays healthy at national scale: database size and run times grow in line with real changes in the register, not exponentially; every run finishes cleanly; a unit that leaves the register stops counting from the day it left. (Owner, 2026-11-09, from the boss's wish: a monthly import from BRREG on rune to exercise the system.)

### Zoom out

Today a BRREG import is a hand-run snapshot (`./cloud.sh import no downloads`) into fixed job slugs (`import_*_2025`). Nothing ends a unit that BRREG deletes: on 2026-11-09 the legal units 879755662 and 969313480, deleted by BRREG on 2026-11-07 after rune's snapshot, were still open-ended on rune. The import strategies map to sql_saga `temporal_merge` modes. Its delete option is never passed, and per-batch processing would make it delete every unit outside the batch, so it cannot close absent units.

### Zoom in

Option C (owner, 2026-11-09): each month, import the full BRREG files, then close the units BRREG deleted. Four jobs a month, in this order (owner, Q1):

1. `import_hovedenhet_YYYY_MM`: legal units, full file, `brreg_hovedenhet_2025` (insert_or_update). New and changed units; an unchanged unit adds no record.
2. `import_underenhet_YYYY_MM`: establishments, full file, `brreg_underenhet_2025`.
3. `import_hovedenhet_slettet_YYYY_MM`: legal unit deletions, `legal_unit_source_dates`.
4. `import_underenhet_slettet_YYYY_MM`: establishment deletions, `establishment_for_lu_source_dates`.

No new import mode. A deletion row is the organisation number, `death_date` = BRREG `slettedato`, and its own `valid_from` = the 1st of the month containing the day before the death (the date_consistency step requires the death to fall after the record's start). BRREG's change feed (`/api/oppdateringer/{enheter,underenheter}`, `endringstype=Sletting`) lists the deletions; the unit lookup gives `slettedato`. The feed reader writes only units StatBus already has; a unit born and deleted within the month is counted, not imported, because an unknown unit without a name stops the job for review. Close, not delete: history keeps the unit until the day it left. A legal unit's establishments close only through their own feed deletions. Scheduling is the statbus user's crontab on rune, on the 2nd of each month (owner, Q2).

Out of scope: unit status from BRREG (bankruptcy, winding-up flags). Every BRREG unit stays Active until deleted; mapping BRREG flags to statuses needs its own design (owner, Q3 pending).

Evidence: `tmp/brreg-feed/`, `tmp/journal.md` and `tmp/600-*-proto.log` in the Rabbit checkout; SQL test 395.

### Closing review

At closing, decide: memory (the monthly job layout and the per-row valid_from rule), documentation (`doc/import-system.md` monthly intake section, `samples/norway/brreg/README.md`), and cleanup (the scratch database `statbus_600_close_proto` and the fixed `import_*_2025` job slugs).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Deletion jobs on the existing definitions close each listed legal unit and establishment on its death date, in the job's month or the previous one, and leave every other unit unchanged (SQL test 395)
- [ ] #2 A monthly BRREG run creates the four jobs for that month (two full files, two deletion lists) and leaves earlier months' jobs untouched
- [ ] #3 [Owner] The rule for a unit missing from the full file with no feed deletion is decided and recorded in Implementation Notes with its consequence, and the run follows it
- [ ] #4 [Owner] The run day and the full-file valid-from date are decided and recorded in Implementation Notes with their consequence (run day decided: the 2nd, Q2)
- [ ] #5 On rune, the first monthly run closes 879755662 and 969313480 at 2026-11-07, and the monthly figures (sizes, rows, run times, closed units) are recorded and reported
- [ ] #6 The statbus user's crontab on rune runs the monthly cycle unattended; a failure stops the cycle and is reported, without retrying
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-09 20:23 UTC design finding (read of statbus_seed definitions and import.analyse_legal_unit, tmp/analyse_legal_unit.sql): the existing legal_unit and establishment definitions already accept death_date_raw, and an update row for a known unit (tax_ident only, no name) is accepted when status resolves. The data model's existence rule (doc/data-model.md, STATBUS-460) ends a unit at death_date without ending its record. So a BRREG deletion with slettedato may need no new import mode: a monthly job row of tax_ident + death_date = slettedato closes the unit from that day. A new close mode is only needed for units missing from the file with no feed entry (no death date; the timeline itself must end). To prove before building: a prototype on a fresh local DB that patches 879755662 with death_date 2026-11-07 and checks existence_until, the Units-over-time chart and the enterprise.

2026-11-09 20:26 UTC prototype CONFIRMED (tmp/journal.md; tmp/600-close-proto-full.{sql,log} legal unit, tmp/600-close-proto-es.{sql,log} establishment; rolled back on scratch DB statbus_600_close_proto). A monthly job on legal_unit_job_provided / establishment_for_lu_job_provided (valid_from 2026-11-01) with rows of only tax_ident + death_date = slettedato finishes with action=use, operation=update, no errors. The unit gets death_date 2026-11-07, keeps name/activity/region/employees, exists on 11-06 and not on 11-08, and so does its enterprise; statistical_history shows deaths=1 in November 2026. An establishment closes alone, its legal unit stays alive. Side effect: the parent legal unit and enterprise get a content-identical record split at the job's valid_from. Consequence: no new 'close units' import mode is needed for feed deletions. The deletion file is just a third and fourth monthly job. The only open case is units missing from the full file with no feed deletion, which would also be closed by a death_date row (the 1st of the month), counted separately in the monthly figures.

2026-11-09 20:28 UTC proposed monthly job layout (owner to confirm): four jobs per month, in this order. (1) import_hovedenhet_YYYY_MM, full file, brreg_hovedenhet_2025, insert_or_update: new and changed legal units. (2) import_underenhet_YYYY_MM, same for establishments (after 1, since establishments refer to their legal unit). (3) import_hovedenhet_slettet_YYYY_MM and (4) import_underenhet_slettet_YYYY_MM: deletions from the change feed, rows of organisation number + death_date = slettedato. Deletions run last, so a deletion wins over a stale row in the full file. Evidence that one full-file job covers insert and update: tmp/600-unchanged-reimport-proto.log (an unchanged unit keeps one record, a changed unit gets a new record from the job's valid_from). Detail to build and test: a deletion row needs a record that starts before its slettedato, so a unit deleted late in the previous month stops counting on that day, not on the 1st.

2026-11-09 20:30 UTC deletions dated before the job's month (tmp/journal.md, tmp/600-late-deletion-proto-c.log): a deletion row with valid_from = the job's 1st of month or = slettedato is rejected (date_consistency: death must fall after the record start). Accepted and correct: the *_source_dates definition with per-row valid_from = 1st of the month containing (slettedato - 1 day). Both test units closed on the exact deletion day, kept their names, and the deaths counted in October and November. So deletion jobs 3 and 4 use legal_unit_source_dates / establishment_for_lu_source_dates (or BRREG equivalents), not the job-provided date.

2026-11-09 20:38 UTC owner confirmed the four monthly jobs (Q1). No new import modes are needed, all four use existing definitions: (1) brreg_hovedenhet_2025 and (2) brreg_underenhet_2025, insert_or_update, job-provided valid_from; (3) legal_unit_source_dates and (4) establishment_for_lu_source_dates, per-row valid_from. Prototype tmp/600-deletion-definitions-proto.log: an establishment deletion closes the establishment and keeps its legal unit link. A deletion for a unit StatBus never had is rejected ('Missing required name') and leaves the job waiting_for_review, which would stall an unattended run. So the feed reader only writes deletions for units StatBus already has and counts the others separately as born and deleted within the month.

2026-11-09 20:41 UTC: c93383eb2 adds SQL test 395 (test/sql/395_statbus_600_monthly_intake_closes_deleted_units.sql), passing locally (tmp/test-395-pass.log). It asserts the monthly intake state on the existing definitions: full-file jobs keep one record for an unchanged unit and add one for a changed unit; deletion jobs close legal units and establishments on the exact death date, whether in the job's month (2026-11-07) or the previous month (2026-10-25); the enterprise follows its legal unit; an establishment death leaves its legal unit alive; a legal unit death leaves its establishments open (the feed reports those separately); Units over time counts deaths in their month. Interview with owner in progress, Q1 (four jobs) answered yes.

2026-11-09 20:42 UTC owner domain input: in Norway activity decides status, but StatBus takes status from BRREG. When a unit shows no activity for a long time BRREG deletes its last establishment and keeps the legal unit; new registrations get both. Fit with the design: test 395 already asserts that an establishment deletion leaves the legal unit alive and linked; new registrations arrive as Ny in both feeds (November sample tmp/brreg-feed: enheter Ny 1094, Sletting 597, Endring 8298, Fjernet 11; underenheter Ny 1637, Sletting 793, Endring 3677, Fjernet 87). Gap: brreg_hovedenhet_2025 and brreg_underenhet_2025 map no status column (konkurs, underAvvikling, underTvangsavvikling..., aktivitet are ignored), so every BRREG unit gets the default status Active. A legal unit left without establishments stays Active and counted. Status mapping added to the owner interview.

2026-11-09 21:16 UTC CI: every workflow for master da4402a41 completed/success (Fast Tests, Go Test, app build & lint, Images, Harness Selftest, Push on master). That commit contains test 395 (c93383eb2). Owner answers so far: Q1 four jobs a month, yes; Q2 run on the 2nd (02:00 Oslo), bringing in the previous month, yes. Q3 BRREG status: open, proposed for its own ticket.

2026-11-09 21:17 UTC AC1 met: SQL test 395 (c93383eb2) passes locally and in CI (master da4402a41, Fast Tests completed/success). It closes legal units on 2026-11-07 (job's month) and 2026-10-25 (previous month) and an establishment on 2026-11-20, leaving the unchanged legal unit 917669791 and the establishment 895406732 open. Owner decision Q2 (20:53): the run is on the 2nd of each month; consequence: it reads the files BRREG built on the 1st, so each run brings in the whole previous month.

2026-11-09 21:23 UTC owner decision Q3: option A. The BRREG loader derives each legal unit's status code from BRREG's flags before upload, as a test bridge until a general design (value mapping in import definitions, more status codes, activity-based status) exists. Consequence: brreg_hovedenhet_2025 gains a mapping from a loader-added status_code column; only Norway gets this. Data: the BRREG legal unit CSV has konkurs, underAvvikling, underTvangsavviklingEllerTvangsopplosning (true/false) plus dates; in the 4,924-row selection sample, 22 under winding-up, 18 bankrupt, 4 under forced winding-up. Next interview question (Q3b): which flags make a unit Passive, given StatBus has only Active and Passive.
<!-- SECTION:NOTES:END -->
