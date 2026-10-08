---
id: STATBUS-467
title: >-
  Seed restore prints a NOTICE for a by-design sequence skip: raise it at DEBUG
  and keep it covered
status: Done
assignee: []
created_date: '2026-10-08 12:10'
updated_date: '2026-10-08 12:25'
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
- [x] #1 The seed-restore path prints no NOTICE for the by-design sequence skip at default verbosity.
- [x] #2 The skip is still observable on demand with client_min_messages=debug and carries the same message text, and the set of skipped non-column-owned sequences is unchanged.
- [x] #3 The change is a new forward migration with CREATE OR REPLACE PROCEDURE; the released migration 20260829114700 is not edited.
- [x] #4 The dedicated test still asserts the skip behaviour by setting the level in the test, and its expected output file is updated deliberately with each moved line explained.
- [x] #5 No other aspect of the procedure's sequence-normalisation behaviour changes, as shown by the existing test.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The before and after seed-restore output is recorded in the ticket, not just the test result.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COORDINATOR FOLLOW-THROUGH 2026-10-08: artifact verified independently of the worker's summary. 5320fcee6 contains the new forward migration 20261008121306 (up 69 lines, down 61) whose diff against its \sf dump changes only RAISE NOTICE to RAISE DEBUG with byte-identical message text; the released 20260829114700 appears nowhere in the commit; the doc/db function file is regenerated in the SAME commit, so the pre-commit pairing requirement is met; test 127 sets client_min_messages=debug around each CALL, so the skipped-sequence set stays pinned while a clean restore prints nothing. The two non-obvious files are comment-only: test/setup.sql rewrites the explanation of its pre-existing SET (no new silencing was added) and cli/cmd/sequence_normalize.go rewrites its doc comment to say the report is now DEBUG. CI note: Go Test and app build & lint show cancelled on 5320fcee6 because a newer push superseded them; the verdict for this tree rides on d4c49da4d.
<!-- SECTION:NOTES:END -->
