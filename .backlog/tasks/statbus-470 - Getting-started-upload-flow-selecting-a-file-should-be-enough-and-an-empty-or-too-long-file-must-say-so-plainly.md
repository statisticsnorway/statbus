---
id: STATBUS-470
title: >-
  Getting-started upload flow: selecting a file should be enough, and an empty
  or too-long file must say so plainly
status: Done
assignee: []
created_date: '2026-10-08 12:30'
updated_date: '2026-10-08 19:23'
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
- [x] #1 With a file selected, confirming the upload uses that file; no second button press is needed. Verified on the local reproduction.
- [x] #2 An empty file, or no file selected, produces a specific sensible message naming what is wrong, never a schema-cache or varchar error.
- [x] #3 A value exceeding the column limit names the offending row, column and limit.
- [x] #4 The same select-then-upload behaviour holds across the getting-started steps, verified in at least two of them.
- [x] #5 Reproduced and verified against a ready local database, with the before and after messages recorded.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The observed before and after messages, and the step where each occurred, are recorded in the ticket.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COORDINATOR VERIFICATION OF THE UPLOAD PATH, 2026-10-08 (read-only, no dispatch). app/src/app/api/import/upload/route.ts: it requires a job slug and streams the file into PostgreSQL with pg-copy-streams, running 'COPY <job.upload_table_name> (<columns>) FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER ,)' at line 365, where <columns> is built from the UPLOADED FILE'S OWN HEADER. So an unexpected column fails at COPY time, and a too-long value fails as PostgreSQL 22001, with the error logged and returned through describeError with status 500. TWO CONSEQUENCES FOR THIS TICKET: (1) because the column list comes from the file header, a file carrying an extra column (such as ActivityCategoryLevel) is rejected by the database rather than by our own validation, which is why Ville's first failure looked like a schema complaint; (2) NOTE A DISCREPANCY to settle during the local reproduction: the message he saw said '... in the schema cache', which is POSTGREST phrasing (PGRST204), while this route talks to PostgreSQL directly and would say 'column ... of relation ... does not exist'. That suggests the getting-started classification upload may reach the database through a different surface than this route, or through an additional PostgREST call. Confirm which surface serves the getting-started upload when reproducing, because it decides where the sensible error must be produced.

SEQUENCING DECISION (owner, 2026-10-08): this is local development work, run against the local development instance when it is ready and not in use by others. No separate deployment slot and no separately provisioned environment. The reproduction waits for the local database to be free - it currently holds the restored February Norway dump that the STATBUS-421 Phase 2 export verification depends on - and then runs there.

SURFACE RESOLVED (coordinator, read-only, 2026-10-08, while the local database is held by 421 Phase 2). The getting-started classification upload does NOT go through app/src/app/api/import/upload/route.ts. It is a Next.js server action: app/src/app/getting-started/getting-started-server-actions.ts builds `${client.url}/${uploadView}` and POSTs the raw CSV straight to POSTGREST (line 35-40), with uploadView = activity_category_enabled_custom supplied by app/src/app/getting-started/upload-custom-activity-standard-codes/page.tsx (line 40). That explains both of Ville's messages exactly: an unexpected column is rejected by PostgREST's own schema cache (PGRST204, hence the wording he saw), not by PostgreSQL as the COPY route would phrase it, and a too-long value comes back as the varchar(256) limit relayed through PostgREST. CONSEQUENCE FOR THIS TICKET: the sensible messages and the select-then-upload behaviour must be produced at THIS surface (the client form plus that server action), and the /api/import/upload route is a different path that the getting-started flow never touches - so do not go looking for the fix there.

PREMISE CORRECTION (coordinator, read-only code reading, 2026-10-08; confirm in the reproduction). The ticket's inference that Ville's first press 'ran with no file actually selected' is probably wrong. app/src/app/getting-started/upload-csv-form.tsx is a single form: a file input marked REQUIRED (lines 76-83) plus one submit button wired through useActionState to uploadFile (lines 55-69), redirecting on success. A browser will not submit that form with no file chosen, so the first press would have uploaded the file he had selected - and the error he got names a column, 'ActivityCategoryLevel', which is exactly what a file whose header does not match the view would produce through PostgREST's schema cache. So the two observed failures are most likely: (a) the CSV's columns did not match the target view, reported cryptically as a PostgREST schema-cache message that neither names the offending column nor says what the view does expect, and (b) a value exceeding the column limit, reported without naming the offending row or column. That reframes the fix away from 'make one press enough' (one press already is enough, given a file) and onto 'make the failure legible at the surface the flow actually uses', while still confirming in the reproduction whether any second press was ever needed. Keep AC1, but test it as written rather than assuming it is broken.

IMPLEMENTED, 2026-10-08, commit 6d2ec4027 (tigress). App-side only: the server action uploadFile (app/src/app/getting-started/getting-started-server-actions.ts) plus a new module app/src/app/getting-started/upload-csv-check.ts. No import-side, SQL or form change was needed.
REPRODUCTION SETUP: the local dev database was replaced with a clone of statbus_seed, which is in sync with HEAD at 20261008183553. The February Norway dump was kept, RENAMED to statbus_local_feb20260210 rather than dropped. Then ./sb users create; settings (nace_v2.1, NO, initial region version) set through PostgREST as jorgen@veridit.no; headless Chromium through the real getting-started pages on the Next dev server (real form, real server action, real PostgREST). Script tmp/470/ui.mjs, files and logs in tmp/470/.
SURFACE CONFIRMED: every press is one server-action POST, and the action POSTs the raw CSV to PostgREST /<view>. The four steps share the form (UploadCSVForm) and the action: upload-custom-activity-standard-codes (activity_category_enabled_custom), upload-regions (region_upload), upload-custom-sectors (sector_custom_only) and upload-custom-legal-forms (legal_form_custom_only).
AC#1 / PREMISE: with a file selected, ONE press uploads it. Observed before AND after: good.csv on the activity step gives 1 server-action POST and navigates to /getting-started/upload-regions, and the rows are in activity_category. No second press was ever needed. With NO file selected the browser does not submit at all, because the input is required: 0 POSTs, validation message 'Please select a file.'. So Ville's first error was a file whose columns did not match, not a missing file. The action also handles the no-file case itself now ('No file selected. Choose a CSV file, then press Upload.') for the case where the browser check is bypassed.
BEFORE (verbatim UI text, step upload-custom-activity-standard-codes unless noted, log tmp/470/before-ui.log):
 - empty file: 'Failed to upload file: parse error (not enough input) at ""'
 - header only, no data rows: SUCCEEDED and navigated on, with nothing imported
 - wrong columns (ActivityCategoryCode,ActivityCategoryLevel,Name): 'Failed to upload file: Could not find the 'ActivityCategoryCode' column of 'activity_category_enabled_custom' in the schema cache'
 - a 600-character name: 'Failed to upload file: value too long for type character varying(512)'
 - Excel CSV UTF-8 (byte-order mark), otherwise correct: 'Failed to upload file: Could not find the '﻿path' column of 'activity_category_enabled_custom' in the schema cache' (the invisible BOM is part of the name)
 - upload-regions, wrong columns: 'Failed to upload file: Could not find the 'Code' column of 'region_upload' in the schema cache'
 - upload-custom-legal-forms, wrong columns: 'Failed to upload file: Could not find the 'Code' column of 'legal_form_custom_only' in the schema cache'
 - upload-custom-sectors, empty file: 'Failed to upload file: parse error (not enough input) at ""'
 - (in code) a non-JSON error body: 'failed to upload in view <view>'
AFTER (verbatim UI text, same steps and files, log tmp/470/after-ui.log):
 - empty file: 'Failed to upload file: The file empty.csv is empty.'
 - header only: 'Failed to upload file: The file empty-header-only.csv has a header row but no data rows.'
 - wrong columns: 'Failed to upload file: The file has columns this step does not accept: ActivityCategoryCode, ActivityCategoryLevel, Name. The accepted columns are: path, name, description. Column names are case-sensitive (Name could be name).'
 - too long: 'Failed to upload file: A value is longer than the column allows (512 characters): row 2 (line 3), column name: 600 characters.'
 - byte-order mark: uploads (BOM stripped), navigates on
 - missing name column: 'Failed to upload file: The file has no name column, which is required.'
 - upload-regions, wrong columns: 'Failed to upload file: The file has columns this step does not accept: Code, RegionName. The accepted columns are: path, name, center_latitude, center_longitude, center_altitude.'
 - upload-custom-legal-forms, wrong columns: 'Failed to upload file: The file has columns this step does not accept: Code, Name. The accepted columns are: code, name. Column names are case-sensitive (Code could be code, Name could be name).'
 - upload-custom-sectors, empty file: 'Failed to upload file: The file empty.csv is empty.'
 - good files, one press each: activity codes go to upload-regions, regions-good.csv goes to upload-custom-sectors, legal-good.csv goes to summary. Rows verified in region (99 Testregion), legal_form (ZZ470) and activity_category (01, 01.1, 01.2).
HOW: the accepted columns and their varchar limits come from PostgREST's own OpenAPI document (the view definition), read only when an upload fails. Without it the message still names the offending column. The too-long check counts characters, not bytes, and blames only columns that carry the reported limit. A semicolon- or tab-separated file is named as such. Any other database error keeps PostgREST's words plus its details and hint.
RED/GREEN (tmp/470/redgreen.log): the test app/src/app/getting-started/getting-started-server-actions.test.ts drives the real uploadFile with PostgREST mocked at the fetch boundary, using the exact responses observed above. Against the UNCHANGED action (checked equal to HEAD): RED, 8 of 9 fail, received 'failed to upload in view activity_category_enabled_custom' (no file, empty, header-only, non-JSON 502), the schema-cache text, 'value too long for type character varying(512)' and the not-null text. Only 'a good file uploads with one request' passes. With the fix: GREEN 9/9. Plus upload-csv-check.test.ts (9 tests: line numbers across quoted newlines/CRLF, character-not-byte lengths, limit-column filtering, semicolon file, no-OpenAPI fallback, empty required value, passthrough).
SUITE: pnpm test 24 suites / 202 tests; lint 0 errors (5 pre-existing warnings elsewhere); tsc clean.
CI for 6d2ec4027: app build & lint 37828421335 success, Go Test 37828421212 success, Images 37828421305 success, Harness Selftest and Push success. Fast Tests 37829021787 still running when this was written; its result is recorded in the next note.

CI COMPLETE for 6d2ec4027, read at job level: Fast Tests 37829021787, job classify = success and job 'pg_regress fast suite' = success (it RAN: '1..116 / All 116 tests passed', plus the isolated test '1..1 / All 1 tests passed'). app build & lint 37828421335 success, Go Test 37828421212 success, Images 37828421305 success, Harness Selftest and Push success. AC#1-5 and DoD#1 checked against the evidence in the previous note. AC#1: one press with a file selected uploads it (it already did, which corrects the ticket's premise); a missing file is stopped by the browser and by the action, each with its own message. AC#2: the empty, header-only and no-file messages. AC#3: row, line, column, length and limit for a too-long value. AC#4: same behaviour verified on four steps (activity codes, regions, legal forms, sectors), with good files in one press on three. AC#5: before and after recorded verbatim on the local seed-clone database.
<!-- SECTION:NOTES:END -->
