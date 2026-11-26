---
id: sxbm3b
title: "Writer and time per changed piece: register sql_saga provenance columns"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzz"
created: 2026-11-26
updated: 2026-11-26
---

## Goal
Every temporal table stamps edit_by_user_id and edit_at on changed pieces only, for edits and imports alike.

## Purpose
sql_saga 1.9+ provenance columns record who changed each piece of history and when; today an untouched piece's writer is lost on some paths (doc/design/provenance.md in sql_saga). Needed for 'Last edited by' on Set as primary and every edit.

## Principle
Provenance takes the column DEFAULT evaluated as the writing role and ignores a supplied value. So imports must write as the uploading user's role (auth.uid() = the uploader), not as the worker's postgres role with an explicit edit_by_user_id. Decide that first; then register the columns per era with sql_saga.set_era_provenance_columns.

## Details
Imports: import.process_* run in the worker as postgres and set edit_by_user_id := v_job.user_id; with provenance that value is replaced by DEFAULT auth.uid(), which is NULL for postgres (column NOT NULL), so every import would fail. Options: the worker sets the job user's role around each process step (SET LOCAL ROLE), or the DEFAULT reads a GUC the worker sets (auth.uid() falls back to it). Requires sql_saga >= 1.10 (1nsdwj brings 1.15).

## Depends on

## Acceptance
- [ ] A SQL test: a regular user's portion edit stamps edit_by_user_id and edit_at on changed pieces only, untouched pieces keep theirs
- [ ] A SQL test: an import job's rows carry the uploading user as writer under provenance
- [ ] [Owner] approves how imports carry the uploader (role switch or GUC) before it is built

## Notes
