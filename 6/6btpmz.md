---
id: 6btpmz
title: "An import can carry unit notes, with the CSV checked in the browser first"
state: todo
type: feature
priority: ""
assignee: ["rabbit"]
labels: ["app", "import"]
group: ""
rank: "x"
created: 2026-11-17
updated: 2026-11-17
---

## Goal
A register import stores each unit's note from a notes column; the browser checks the CSV before upload and names a broken line.

## Purpose
Owner 2026-11-17 19:09: notes support in imports is its own task, split from n9nyvd (the side-column notes box). An office keeps notes elsewhere and brings them in; CSV text with quotes and line breaks is where imports break.

## Principle
Strict, early CSV validation: the file is checked where the user is, before anything is sent. A notes cell follows the import strategy settled in dbmsxy, through the same sql_saga temporal_merge machinery; no notes-only rule.

## Relevant details
Papa Parse checks the file in the browser and refuses a broken one with the line where it breaks. Today the upload route (app/src/app/api/import/upload/route.ts) streams the file into PostgreSQL COPY (FORMAT csv). An unterminated quote swallows every following line, so COPY rejects the whole file (tmp/n9nyvd-unterminated-copy.log: 'unterminated CSV quoted field', line 5); no row-level isolation is possible after it. Papa Parse in the browser can find the line where the open quote starts. Strategies: public.import_strategy = insert_or_replace, insert_only, replace_only, insert_or_update, update_only; sql_saga.temporal_merge modes MERGE_ENTITY_REPLACE / MERGE_ENTITY_PATCH / MERGE_ENTITY_UPSERT decide whether a NULL overwrites. unit_notes is timeless (no valid range): which merge mode each strategy uses is settled in dbmsxy; how that applies to a table without periods is check 3 here. CSV traps to test: doubled quotes, commas, CR/LF and CRLF inside quoted fields, unterminated quotes, leading/trailing spaces.

## Depends on

- dbmsxy
## Acceptance
- [ ] An upload whose notes column has an unterminated quote is refused in the browser before upload, naming the line where the open quote starts; nothing is sent
- [ ] An import with a notes column stores each unit's note; a test file with doubled quotes, commas and line breaks inside quoted notes stores them exactly, and a unit on several rows follows the owner's settlement in the next check
- [ ] [Owner] Settles, per import strategy, what an empty and a filled notes cell do to the unit's note (unit_notes is timeless), and whether a unit on several rows (periods) has its notes merged into one or the file refused; recorded in this task's notes; each settled case becomes a case of the tests in checks 2 and 4
- [ ] An empty and a filled notes cell follow the import's strategy, as settled in check 3; a test per strategy asserts the stored note equals the settled result

## Notes

2026-11-17 23:33 (Rabbit) moved from n9nyvd: tmp/n9nyvd-unterminated-copy.log shows the upload's COPY (FORMAT csv) rejects the whole file on an unterminated quote ('unterminated CSV quoted field', line 5): the open quote swallows every following line, so no row-level isolation is possible after it. Owner 19:09: address it with Papa Parse in the browser, naming the line where the open quote starts (check #1).

2026-11-21 19:49 (Rabbit) Parked by the owner. A unit's note has no periods, so an import file that carries several rows (periods) for one unit must have one note win. Either the analyse phase merges them into one note or it refuses the file. My question about what an empty cell does under each strategy came from not knowing how the import engine handles cells yet. This waits for the owner's tasks that improve the import jobs; take it up again after those.

2026-11-21 (Rabbit) The strategy questions for notes are part of dbmsxy (which merge mode each strategy uses, and that a column the file does not carry is never written).
