---
id: 6btpmz
title: "An import can carry unit notes, with the CSV checked in the browser first"
state: todo
type: feature
priority: ""
assignee: []
labels: ["app", "import"]
created: 2026-11-17
updated: 2026-11-17
---

## Goal
A register import brings each unit's notes from a notes column into public.unit_notes, and the browser checks the CSV with Papa Parse before upload, refusing a broken file with the line where it breaks.

## Purpose
Owner 2026-11-17 19:09: notes support in imports is its own task, split from n9nyvd (the side-column notes box). An office keeps notes elsewhere and brings them in; CSV text with quotes and line breaks is where imports break.

## Principle
Strict, early CSV validation: the file is checked where the user is, before anything is sent. An empty notes cell is handled like every other import column, by the definition's strategy (insert_or_replace replaces, insert_or_update and update_only patch), through the same sql_saga temporal_merge machinery; no notes-only rule.

## Relevant details
Today the upload route (app/src/app/api/import/upload/route.ts) streams the file into PostgreSQL COPY (FORMAT csv). An unterminated quote swallows every following line, so COPY rejects the whole file (tmp/n9nyvd-unterminated-copy.log: 'unterminated CSV quoted field', line 5); no row-level isolation is possible after it. Papa Parse in the browser can find the line where the open quote starts. Strategies: public.import_strategy = insert_or_replace, insert_only, replace_only, insert_or_update, update_only; sql_saga.temporal_merge modes MERGE_ENTITY_REPLACE / MERGE_ENTITY_PATCH / MERGE_ENTITY_UPSERT decide whether a NULL overwrites. unit_notes is timeless (no valid range): how a strategy maps onto a non-temporal table is part of this task, and the owner returns to it. CSV traps to test: doubled quotes, commas, CR/LF and CRLF inside quoted fields, unterminated quotes, leading/trailing spaces.

## Depends on

## Acceptance
- [ ] An upload whose notes column has an unterminated quote is refused in the browser before upload, naming the line where the open quote starts; nothing is sent
- [ ] An import with a notes column stores each row's note; a test file with doubled quotes, commas and line breaks inside quoted notes stores them exactly
- [ ] [Owner] Settles how the import strategies apply to unit_notes (a timeless table), recorded in this task's notes
- [ ] An empty notes cell follows the job's strategy as settled; a test per strategy shows the stored notes

## Notes
