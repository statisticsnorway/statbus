---
id: STATBUS-467
title: >-
  Seed restore prints a NOTICE for a by-design sequence skip: raise it at DEBUG
  and keep it covered
status: In Progress
assignee: []
created_date: '2026-10-08 12:10'
updated_date: '2026-10-08 12:11'
labels:
  - sql
  - devx
dependencies: []
priority: medium
ordinal: 393204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the seed-restore path prints nothing that looks alarming when nothing is wrong, and the diagnostic it currently prints is still available when someone asks for it.

WHAT HAPPENS. Restoring the seed to statbus_local prints, in the middle of otherwise clean output:

NOTICE: 00000: normalize_all_sequences: skipped graphql.seq_schema_version, public.import_job_priority_seq, public.power_group_ident_seq, public.worker_task_priority_seq (no owning column to derive an authoritative max from -- this procedure only ever normalizes column-owned sequences)

It comes from public.normalize_all_sequences, migration 20260829114700_add_normalize_all_sequences_procedure.up.sql line about 97, which raises that text as a NOTICE. It appears during the seed restore because test/setup.sql line 118 calls the procedure.

WHY THAT IS WRONG. Skipping sequences that are not owned by a column is the procedure's documented, intended behaviour, so NOTICE, the default level a client shows, is the wrong severity: it reads like a warning during a clean restore. The information itself is fine and useful; only its level is wrong.

REQUIRED FIX.
1. Deliver the change as a NEW forward migration using CREATE OR REPLACE PROCEDURE. Do not edit the released migration 20260829114700; released migrations are immutable. Dump the current definition first (echo "\sf public.normalize_all_sequences" | ./sb psql), keep the message text byte for byte, and change only the level to DEBUG.
2. Do NOT silence it by hiding all notices at the caller, for example by setting client_min_messages in test/setup.sql; that would suppress unrelated notices too and hide real problems.
3. Keep the coverage: test/sql/127_statbus_316_normalize_all_sequences.sql should set client_min_messages=debug around its CALL so the skip message is still asserted, and test/expected/127_statbus_316_normalize_all_sequences.out updated deliberately, with each moved line explained in the ticket rather than regenerated blindly.
4. Nothing else about the normalisation behaviour changes.

EVIDENCE TO RECORD: the seed-restore output before and after, showing the NOTICE gone at default verbosity and still present with client_min_messages=debug, plus the test run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The seed-restore path prints no NOTICE for the by-design sequence skip at default verbosity.
- [ ] #2 The skip is still observable on demand with client_min_messages=debug and carries the same message text, and the set of skipped non-column-owned sequences is unchanged.
- [ ] #3 The change is a new forward migration with CREATE OR REPLACE PROCEDURE; the released migration 20260829114700 is not edited.
- [ ] #4 The dedicated test still asserts the skip behaviour by setting the level in the test, and its expected output file is updated deliberately with each moved line explained.
- [ ] #5 No other aspect of the procedure's sequence-normalisation behaviour changes, as shown by the existing test.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The before and after seed-restore output is recorded in the ticket, not just the test result.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner question 2026-10-08: this warning seems nonsensical, can we quiesce it or not emit it? Answer: skipping non-column-owned sequences is by design, so the level is the defect; DEBUG keeps the diagnostic available on request while the restore stays clean.
<!-- SECTION:NOTES:END -->
