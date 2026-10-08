---
id: STATBUS-470
title: >-
  Getting-started upload flow: selecting a file should be enough, and an empty
  or too-long file must say so plainly
status: To Do
assignee: []
created_date: '2026-10-08 12:30'
updated_date: '2026-10-08 15:59'
labels:
  - app
  - import
  - devx
dependencies: []
priority: high
ordinal: 396204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: choosing a file and pressing upload is enough, and a bad file says plainly what is wrong with it.

FIELD REPORT (Ville, 2026-10-08, screenshot). Importing an ActivityCategories CSV: after selecting the file he pressed Upload and got 'Failed to upload file: Could not find the ActivityCategoryLevel column of activity_category_enabled_custom in the schema cache'. Pressing Upload again surfaced the next hurdle, 'varchar is set to 256, at least 1 of my lines is too long'. His own correction of the first: he needed to press Upload after selecting the file, which implies the first attempt ran with no file actually selected and produced a nonsensical schema-cache error rather than saying 'no file selected'.

OWNER DIRECTIVE.
1. Selecting a file should be sufficient. Confirming the upload must use the selected file instead of requiring a second button press, and the same pattern must hold across the getting-started and bootstrap steps so this class of error cannot happen at all.
2. An empty file, or no file selected, must produce a sensible message that says exactly that, never a schema-cache or varchar error.
3. A value that is too long must name the offending row, the column and the limit, so the operator can fix the file without guessing.

PREREQUISITE AND TIMING (owner): reproduce locally once the local database is ready, after the other work in flight. The local DB currently holds the restored February Norway dump, so this flow needs a working install or seed first.

SCOPE: the upload UX in the getting-started/bootstrap steps, from file selection through upload confirmation, and the messages those steps produce. Not the import pipeline's validation semantics beyond those messages.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With a file selected, confirming the upload uses that file; no second button press is needed. Verified on the local reproduction.
- [ ] #2 An empty file, or no file selected, produces a specific sensible message naming what is wrong, never a schema-cache or varchar error.
- [ ] #3 A value exceeding the column limit names the offending row, column and limit.
- [ ] #4 The same select-then-upload behaviour holds across the getting-started steps, verified in at least two of them.
- [ ] #5 Reproduced and verified against a ready local database, with the before and after messages recorded.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The observed before and after messages, and the step where each occurred, are recorded in the ticket.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COORDINATOR VERIFICATION OF THE UPLOAD PATH, 2026-10-08 (read-only, no dispatch). app/src/app/api/import/upload/route.ts: it requires a job slug and streams the file into PostgreSQL with pg-copy-streams, running 'COPY <job.upload_table_name> (<columns>) FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER ,)' at line 365, where <columns> is built from the UPLOADED FILE'S OWN HEADER. So an unexpected column fails at COPY time, and a too-long value fails as PostgreSQL 22001, with the error logged and returned through describeError with status 500. TWO CONSEQUENCES FOR THIS TICKET: (1) because the column list comes from the file header, a file carrying an extra column (such as ActivityCategoryLevel) is rejected by the database rather than by our own validation, which is why Ville's first failure looked like a schema complaint; (2) NOTE A DISCREPANCY to settle during the local reproduction: the message he saw said '... in the schema cache', which is POSTGREST phrasing (PGRST204), while this route talks to PostgreSQL directly and would say 'column ... of relation ... does not exist'. That suggests the getting-started classification upload may reach the database through a different surface than this route, or through an additional PostgREST call. Confirm which surface serves the getting-started upload when reproducing, because it decides where the sensible error must be produced.

SEQUENCING DECISION (owner, 2026-10-08): this is local development work, run against the local development instance when it is ready and not in use by others. No separate deployment slot and no separately provisioned environment. The reproduction waits for the local database to be free - it currently holds the restored February Norway dump that the STATBUS-421 Phase 2 export verification depends on - and then runs there.

SURFACE RESOLVED (coordinator, read-only, 2026-10-08, while the local database is held by 421 Phase 2). The getting-started classification upload does NOT go through app/src/app/api/import/upload/route.ts. It is a Next.js server action: app/src/app/getting-started/getting-started-server-actions.ts builds `${client.url}/${uploadView}` and POSTs the raw CSV straight to POSTGREST (line 35-40), with uploadView = activity_category_enabled_custom supplied by app/src/app/getting-started/upload-custom-activity-standard-codes/page.tsx (line 40). That explains both of Ville's messages exactly: an unexpected column is rejected by PostgREST's own schema cache (PGRST204, hence the wording he saw), not by PostgreSQL as the COPY route would phrase it, and a too-long value comes back as the varchar(256) limit relayed through PostgREST. CONSEQUENCE FOR THIS TICKET: the sensible messages and the select-then-upload behaviour must be produced at THIS surface (the client form plus that server action), and the /api/import/upload route is a different path that the getting-started flow never touches - so do not go looking for the fix there.
<!-- SECTION:NOTES:END -->
