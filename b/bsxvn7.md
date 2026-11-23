---
id: bsxvn7
title: "An import without a data source column uses the job's data source"
state: todo
type: bug
priority: "high"
assignee: []
labels: []
group: ""
rank: "zzzzzz"
created: 2026-11-22
updated: 2026-11-22
---

## Goal
Each row of an import job gets a data source: the job's chosen one or the file's own column, by the owner's rule.

## Purpose
Norway (rune) job 13 (owner 2026-11-22; Erik, legal_unit_job_provided, 2026-11-13): the job's data source nlr is on none of its 5 rows nor on the 5 legal_unit rows it wrote (checked read-only 2026-11-23). Units imported without a data source cannot be traced to where their data came from.

## Principle
The fix is for later jobs: a failed or wrong job stays as it was, and the user clones it after the release to see the new behaviour. Dates already work this way (valid_from_raw falls back to the job's default_valid_from).

## Details
Mechanism: the job stores its choice in import_job.default_data_source_code, but the six unit definitions map data_source_code_raw only from a file column, never from the job. admin.import_job_prepare already turns source_expression 'default' on data_source_code_raw into the job's default_data_source_code; no definition uses it for data source. Dates already work this way (valid_from_raw falls back to default_valid_from).

## Depends on

## Acceptance
- [ ] [Owner] Decides which wins per row when the file has a data source column and the job has one chosen (the file's value, or the job's choice); recorded here, and the SQL test in check 3 asserts that rule
- [ ] A legal unit import whose file has no data source column, with a data source chosen for the job, stores that data source on every unit row; a SQL test asserts it
- [ ] With a data source column in the file, the rows follow the owner's rule; a SQL test asserts it
- [ ] On no.statbus.org (rune) after the release, a clone of job 13 stores data source nlr on its rows and on the legal units it writes; the result is recorded here

## Notes
