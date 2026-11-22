---
id: 2tsdqp
title: "Analysis refuses a row that processing would fail"
state: todo
type: bug
priority: "high"
assignee: []
labels: []
group: ""
rank: "zzzzy"
created: 2026-11-21
updated: 2026-11-21
---

## Goal
A row analysis passes as 'use' is written by processing without error; a row that cannot be written is refused in analysis.

## Purpose
Jobs in Norway (Erik, 2026-11-11: 'null value in column name of relation establishment', 'Must have either legal_unit_id or enterprise_id') and in dev (Hedda, owner 2026-11-21) failed in processing after analysis passed them. A failure in processing is late: the user cannot fix it from the analysis view, and part of the job may already be applied.

## Principle
Analysis is the gate: it checks what the chosen merge mode will need from each row against the target as it is, so processing errors mean a bug in analysis, not in the file.

## Relevant details
Cause found for the Norway case (rolled-back prototype 2026-11-21, tmp/slack-todos/modes-bd.log): analyse_legal_unit and analyse_establishment require a name only when the unit is new (legal_unit_id IS NULL); analyse_valid_time checks only valid_from < valid_until. Nothing compares the row's period with the existing unit's life. With MERGE_ENTITY_PATCH (insert_or_update, the seeded default), a row whose period starts before the unit existed inserts that earlier stretch from the file's columns alone, so NOT NULL columns (name; the establishment's legal_unit_id/enterprise_id link) are missing and processing fails. The dev failures are not yet inspected: the owner looks at them (2026-11-21). Related: dbmsxy (update only given columns).

## Depends on

## Acceptance
- [ ] [Owner] Inspects the failing jobs on Norway and dev and records each job id, its error and whether it is this cause, in this task's notes
- [ ] A legal unit update row without a name whose period starts before the unit existed is refused in analysis with a message naming the unit's first date; a SQL test asserts the row's state, action and error
- [ ] The same for an establishment update row without its legal unit link; a SQL test asserts it
- [ ] On dev after the release, a clone of job 5 finishes with no processing error: its 48 sector rows are refused in analysis with the sector message and nothing else fails; the result is recorded here
- [ ] An establishment-of-legal-unit row with a sector code is refused in analysis with a message saying the sector belongs to its legal unit; a SQL test asserts the row's state, action and error
- [ ] A row that fails in processing fails alone: the other rows' units, statistics, contacts and activities are written; a SQL test with one bad row asserts the rest are processed
- [ ] An upload for establishments of legal units whose file has a column an establishment cannot hold (sector, legal form) is refused on the upload page with a message naming the column; a Playwright test asserts it

## Notes

2026-11-22 (Rabbit) dev.statbus.org jobs 5 and 6 inspected read-only (tmp/slack-todos/dev-jobs.log). Both establishment_for_lu_job_provided, the same 7642-row file; analysis refused 7592 (legal unit not found) and passed 48. Job 5's file had a sector column: the 48 rows carried sector 8300, processing failed with 'new row for relation establishment violates check constraint enterprise_id enables sector_id' (an establishment of a legal unit cannot hold a sector, its legal unit does). Their stat_for_unit rows then failed ('One and only one statistical unit id must be set'), and process_contact and process_activity failed as a batch for all 7642 rows; job state failed. Job 6, same file without the sector column: 48 processed, finished. Job 5 also ignored legal_form, legal unit stat/tax ident, stat_ident and tax_ident columns. Owner 2026-11-22: columns an establishment cannot hold must not be offered or silently ignored; the upload refuses them with a message.
