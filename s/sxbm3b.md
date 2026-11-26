---
id: sxbm3b
title: "Activate sql_saga provenance once imports write as the uploading user"
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
Imports write as the uploading user's role, and every temporal table then stamps writer and time on changed pieces only.

## Purpose
sql_saga 1.9+ provenance columns record who changed each piece of history and when; today an untouched piece's writer is lost on some paths (doc/design/provenance.md in sql_saga). Needed for 'Last edited by' on Set as primary and every edit.

## Principle
Provenance does nothing until an era is registered, so the sql_saga 1.15 upgrade (1nsdwj) leaves writer behaviour unchanged. This task does both halves in one change, never one without the other: make the worker run each import step as the job's user (SET LOCAL ROLE, as the app's requests do, so RLS also applies), prove it with the import tests, then register edit_by_user_id and edit_at as provenance columns on every era.

## Details
Today import.process_* run in the worker as postgres and set edit_by_user_id := v_job.user_id; provenance takes DEFAULT auth.uid() (= the role's user) and ignores a supplied value, so imports must run as the uploader before provenance is switched on. Check: the worker's role switch with RLS for regular_user (policy edit_by_user_id = auth.uid()), temp tables created across a role switch (test.remove_pg_temp_for_tx_user_switch shows the hazard), and the worker's crash recovery. Requires sql_saga >= 1.10 (1nsdwj).

## Depends on

- 1nsdwj
## Acceptance
- [ ] A SQL test: a regular user's portion edit stamps edit_by_user_id and edit_at on changed pieces only, untouched pieces keep theirs
- [ ] A SQL test: an import job's rows carry the uploading user as writer under provenance
- [ ] [Owner] approves how imports carry the uploader (role switch or GUC) before it is built
- [ ] A SQL test: an import job's rows carry the uploading user as writer, with the worker switching to that user's role
- [ ] A SQL test: a regular user's portion edit stamps edit_by_user_id and edit_at on changed pieces only; untouched pieces keep theirs
- [ ] The fast SQL suite passes with provenance on every era

## Notes
