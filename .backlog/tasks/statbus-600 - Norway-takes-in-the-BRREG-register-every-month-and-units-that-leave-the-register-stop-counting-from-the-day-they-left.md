---
id: STATBUS-600
title: >-
  Norway takes in the BRREG register every month, and units that leave the
  register stop counting from the day they left
status: To Do
assignee:
  - '@rabbit'
created_date: '2026-11-09T18:50:00Z'
updated_date: '2026-11-09T20:23:00Z'
labels:
  - import
  - norway
  - brreg
dependencies: []
priority: high
ordinal: 516204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star

Norway (rune) takes in the BRREG register every month with no manual steps. The monthly figures show StatBus stays healthy at national scale: database size and run times grow in line with real changes in the register, not exponentially; every run finishes cleanly; a unit that leaves the register stops counting from the day it left. (Owner, 2026-11-09, from the boss's wish: a monthly import from BRREG on rune to exercise the system.)

### Zoom out

Today a BRREG import is a hand-run snapshot (`./cloud.sh import no downloads`) into fixed job slugs (`import_*_2025`). Nothing ends a unit that BRREG deletes: on 2026-11-09 the legal units 879755662 and 969313480, deleted by BRREG on 2026-11-07 after rune's snapshot, were still open-ended on rune. The import strategies map to sql_saga `temporal_merge` modes. Its delete option is never passed, and per-batch processing would make it delete every unit outside the batch, so it cannot close absent units.

### Zoom in

Option C (owner, 2026-11-09): each month, import the full BRREG files as new jobs, then close every unit missing from the file. BRREG's change feed (`/api/oppdateringer/{enheter,underenheter}`) marks a deletion with `endringstype=Sletting`, and the unit lookup gives the exact `slettedato`. A closed unit's timeline ends at that date and its `death_date` is set to it. Close, not delete: history keeps the unit until the day it left. The closing is a new generic import mode, "close units" (identifier, end date, death date), usable by any office. Scheduling is the statbus user's crontab on rune.

Open owner questions: run day and time, valid-from date, units missing with no feed entry, scope (relationships), behaviour during an upgrade, where the monthly figures go.

Evidence of the gap and the feed: `tmp/brreg-feed/` in the Rabbit checkout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A close-units import mode ends each listed unit's timeline at the given date and sets its death date, and leaves every other unit unchanged
- [ ] #2 A monthly BRREG import creates new jobs for that month on the existing BRREG definitions, valid from the agreed date, and leaves earlier months' jobs untouched
- [ ] #3 Units BRREG deleted since the previous run are closed at their BRREG deletion date with that death date; units missing with no feed entry follow the agreed rule
- [ ] #4 On rune, the first monthly run closes 879755662 and 969313480 at 2026-11-07, and the monthly figures (sizes, rows, run times, closed units) are recorded and reported
- [ ] #5 The statbus user's crontab on rune runs the monthly cycle unattended; a failure stops the cycle and is reported, without retrying
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-09 20:23 UTC design finding (read of statbus_seed definitions and import.analyse_legal_unit, tmp/analyse_legal_unit.sql): the existing legal_unit and establishment definitions already accept death_date_raw, and an update row for a known unit (tax_ident only, no name) is accepted when status resolves. The data model's existence rule (doc/data-model.md, STATBUS-460) ends a unit at death_date without ending its record. So a BRREG deletion with slettedato may need no new import mode: a monthly job row of tax_ident + death_date = slettedato closes the unit from that day. A new close mode is only needed for units missing from the file with no feed entry (no death date; the timeline itself must end). To prove before building: a prototype on a fresh local DB that patches 879755662 with death_date 2026-11-07 and checks existence_until, the Units-over-time chart and the enterprise.
<!-- SECTION:NOTES:END -->
