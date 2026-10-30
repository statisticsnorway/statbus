---
id: STATBUS-545
title: >-
  Re-upload and clone fail when the file has a column the import definition no
  longer maps (employees after stat disabled)
status: To Do
assignee: []
created_date: '2026-10-30T14:30:00Z'
updated_date: '2026-10-30T14:32:00Z'
labels:
  - import
  - upload
  - clone
dependencies: []
priority: medium
type: bug
ordinal: 471204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: a downloaded job file can always be re-uploaded into a cloned job; columns the current definition no longer maps are kept, shown, and reported, never a hard failure.

### Zoom out
Owner workflow: download a job's rows, clone the job, fix rows locally, upload the file again, run. Definitions change between runs (a statistical variable disabled, a source column removed), so the file can carry a column the new job does not map.

### Zoom in
Dev job 38 (establishments) has upload column employees; stat_definition 17 employees was disabled on dev afterwards, import.cleanup_orphaned_synced_mappings removed its source column, so new jobs of definition 3 lack it. Download (api/import/download) exports from the job's definition_snapshot, so the file keeps employees. Re-upload (api/import/upload) COPYs every header into the upload table and fails: ERROR column "employees" of relation "import_job_46_upload" does not exist (tmp/c6-repro.sql, tmp/c6-repro.log, rolled back on the local dev copy). public.import_job_clone fails the same way (INSERT ... SELECT * : more expressions than target columns; journal 2026-10-30 13:08).

Design (agreed with owner 2026-10-30 14:26-14:29):
- Upload and clone accept a column the definition does not map: it is added to the upload table and loaded as is.
- The data table gets it as a display-only column named <col>_raw (employees_raw), never read by any import step; there is no mapped employees column.
- Row warning: each row with a value in that column gets a warning keyed <col>_raw, the same key style as existing row warnings.
- Column warning: one warning for the column, keyed <col>_raw, shown on the column header. Job-level fields are named singular (warning, error).
- Download stays as is.

### Closing review
Document the behaviour in doc/import-system.md; regenerate doc/db; check the UI renders column warnings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test 305 (extended, no new file): disable a statistical variable used by an imported job, clone the job: the clone succeeds and its upload table keeps the column; fails before the fix
- [ ] #2 Re-upload through api/import/upload of a file with that column succeeds; the COPY no longer errors
- [ ] #3 Job page shows the column warning on the column header
- [ ] #4 Fast Tests green in CI for the commit
- [ ] #5 Data table has a display-only <col>_raw column that no import step reads, and no mapped <col> column
- [ ] #6 Each row with a value in that column has a warning keyed <col>_raw
- [ ] #7 The column has one warning keyed <col>_raw, and imported values are otherwise identical to the original job
- [ ] #8 The data column is marked purpose 'ignored' in the job's definition_snapshot, has no mapping, and no import step reads it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
14:32 Design decision (owner): the data column for a file header the definition no longer maps is marked with a new import_data_column_purpose value 'ignored' (owner rejected 'unmapped_input'). It lives only in the job's definition_snapshot import_data_column_list as {column_name: <col>_raw, purpose: ignored, column_type: TEXT}; the shared import_data_column table is untouched. Meaning: a column from the uploaded file that this job keeps and shows but never processes. Import steps select by purpose, so they skip it; the job page shows it greyed with the column warning on its header; download includes it so round trips keep it; no <col> data column exists. Invariant: an 'ignored' column has no mapping, asserted where the snapshot is built and in test 305.
<!-- SECTION:NOTES:END -->
