---
id: n9nyvd
title: "A unit's notes sit in the side column of every unit page, and an import can carry them"
status: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: ["app", "import"]
created: 2026-11-17
updated: 2026-11-17
model: "claude-opus-5-5"
branch: "statbus-628-all-forms"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
A user reads, adds and edits a unit's notes from any of its pages, in the side column under the menu, and a register import can bring notes in from a notes column.

## Purpose
Owner review 2026-11-17: once the primary-unit box moves into the edit form (acdq9d), its space can hold the unit's notes. They are then visible everywhere, grow with their content, and the first note can be added there. A notes column in the import lets an office bring the notes it keeps elsewhere.

## Principle
Notes are timeless: one current text per unit, not dated by a time frame. A note is the user's own working aid. In a CSV the notes column is checked strictly; a broken quote or line break fails that row clearly.

## Relevant details
public.unit_notes holds one notes text per unit (unique on establishment, legal unit, enterprise, power group), edit_by_user_id and edit_at, with RLS; public.notes_for_unit(...) reads it. 0 rows locally. No import definition has a notes column yet. CSV traps: embedded quotes (doubled), commas, CR/LF and CRLF inside quoted fields, unterminated quotes, leading/trailing spaces, empty value (keep the note or clear it: to decide). Depends on acdq9d freeing the space.

## Depends on

## Acceptance
- [x] Every legal unit and establishment page shows the unit's notes under the menu; the box grows with the text
- [x] A unit without notes offers 'Add a note' there; saving stores one unit_notes row with the editor and time
- [x] Editing a note from any of the unit's pages updates the same row
- [ ] An import with a notes column stores each row's note; a test file with doubled quotes, commas and line breaks inside quoted notes stores them exactly
- [ ] An unterminated quote in the notes column fails that row with an error naming the row and column, and the rest of the file is unaffected
- [ ] With the owner's choice for an empty notes cell recorded in this task's notes, an import applies it: 'keep' leaves the unit's existing note untouched; 'clear' deletes it (a test shows each)

## Notes

2026-11-17 13:48 side-column notes built on branch (Rabbit), commit 617f1f125. notesWrite (insert first / update / delete when emptied / none when unchanged) RED tmp/n9nyvd-red.log, GREEN tmp/n9nyvd-green.log; jest 440, tsc ok, lint 0 errors (tmp/n9nyvd-checks.log). UnitNotesBox in DetailsPageLayout's aside (all LU/EST/ENT tabs), reads/writes public.unit_notes via /rest under its RLS. Headless tmp/n9nyvd-check.log on LU 29: Add a note with comma, quotes and a line break stored exactly with edit_by_user_id 4; shown on Contact; edited there; emptied -> row deleted (DB ends as it began). Screenshot tmp/n9nyvd/added.png. Remaining: import notes column (#4, #5) and owner's empty-cell decision (#6).

2026-11-17 13:50 finding for check #5 (Rabbit, tmp/n9nyvd-unterminated-copy.log): the upload streams the file into PostgreSQL COPY (FORMAT csv). An unterminated quote makes the quoted field swallow every following line until EOF, so COPY rejects the whole file ('unterminated CSV quoted field ... line 5'); no row-level isolation is possible after that point, because the rest of the file is inside the open quote. '#5: the rest of the file is unaffected' cannot hold as written. Options for the owner: (a) the upload refuses the file and names the line where the open quote starts (Papa.parse already reads the file in the route and can find it before COPY), or (b) keep row isolation only for quote errors that close on the same line. Proposal: (a).
