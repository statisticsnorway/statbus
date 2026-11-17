---
id: n9nyvd
title: "A unit's notes sit in the side column of every unit page as a sticky note"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: ["app"]
created: 2026-11-17
updated: 2026-11-17
model: "claude-opus-5-5"
branch: "statbus-628-all-forms"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
A user reads, adds and edits a unit's notes from any of its pages, in a yellow sticky note in the side column under the menu, and sees who last wrote the note and when.

## Purpose
Owner review 2026-11-17: once the primary-unit box moves into the edit form (acdq9d), its space can hold the unit's notes. They are then visible everywhere, grow with their content, and the first note can be added there. Owner 19:09: it should look like a sticky note, be edited from a pencil at its right, and say who wrote it. Notes in imports are their own task (6btpmz).

## Principle
Notes are timeless: one current text per unit, not dated by a time frame. A note is the user's own working aid; the row's edit_by_user_id and edit_at name its last writer.

## Relevant details
public.unit_notes holds one notes text per unit (unique on establishment, legal unit, enterprise, power group), created_at, edit_comment, edit_by_user_id (default auth.uid()) and edit_at (default statement_timestamp()), with RLS: a regular user writes only rows naming himself (WITH CHECK edit_by_user_id = auth.uid()), an admin any row. No trigger refreshes edit_by_user_id or edit_at on update (tmp/n9nyvd-editor-probe.log), so the app's update sets both. The side column space comes from acdq9d.

## Depends on
- acdq9d

## Acceptance
- [x] Every legal unit and establishment page shows the unit's notes under the menu; the box grows with the text
- [x] A unit without notes offers 'Add a note' there; saving stores one unit_notes row with the editor and time
- [x] Editing a note from any of the unit's pages updates the same row
- [x] The box is sticky-note yellow, and a pencil at the right of its heading adds or edits the note (no text links)
- [x] Under the note the box names who last wrote it and when; a regular user editing a note someone else wrote saves it, and the row then names that user and the new time
- [x] Two users editing the same note: a save applies only over the version its editor loaded (edit_at); a save that finds a newer note or a first note added meanwhile shows the other's text, who and when, keeps the draft, and saves only when pressed again

## Notes

2026-11-17 13:48 side-column notes built on branch (Rabbit), commit 617f1f125. notesWrite (insert first / update / delete when emptied / none when unchanged) RED tmp/n9nyvd-red.log, GREEN tmp/n9nyvd-green.log; jest 440, tsc ok, lint 0 errors (tmp/n9nyvd-checks.log). UnitNotesBox in DetailsPageLayout's aside (all LU/EST/ENT tabs), reads/writes public.unit_notes via /rest under its RLS. Headless tmp/n9nyvd-check.log on LU 29: Add a note with comma, quotes and a line break stored exactly with edit_by_user_id 4; shown on Contact; edited there; emptied -> row deleted (DB ends as it began). Screenshot tmp/n9nyvd/added.png.

2026-11-17 19:17 owner review 19:09 built (Rabbit), commit fac21f02f. Box is sticky-note yellow (bg-yellow-100), a pencil at the right of the heading adds/edits (the 'Add a note'/'Edit note' links are gone), and under the text '<display name>, yyyy-MM-dd HH:mm' from edit_by_user_id/edit_at. Bug fixed: an edit only sent {notes}, so the row kept its first writer and time and a regular user could not save a note written by someone else (RLS WITH CHECK edit_by_user_id = auth.uid()); tmp/n9nyvd-editor-probe.log. notesWrite's update now carries edit_by_user_id and edit_at: RED tmp/n9nyvd-editor-red.log, GREEN tmp/n9nyvd-editor-green.log; jest 440, tsc 0, lint 0 errors. Headless tmp/n9nyvd-check2.mjs/.log + tmp/n9nyvd/lu28-*.png, lu29-owner-note.png: LU 29 shows the owner's note 'Jørgen Hermanrud Fjeld, 2026-11-17 20:03' (read only); on LU 28 the regular user added a note (row by 4), the row was then set to user 1 at 2026-01-02, the regular user edited it with no error and the row named 4 and today; emptied, row gone. Database ends as it began. Import split to 6btpmz.

2026-11-17 23:32 (Rabbit) owner 23:20: yellow toned down to bg-yellow-50 / border-yellow-200, typing area white (4d9a11584). Owner 23:29: race on notes. Fixed in 076553008: edit_at is the note's version; update and delete send edit_at=eq.<loaded> and return the rows touched; none (or a 23505 on a first note) means someone else saved: the box reloads, shows their text, who and when in an amber box above the kept draft; Save then replaces theirs knowingly, Cancel keeps theirs. Prototype tmp/n9nyvd-race-probe.log (UPDATE 0 after another save). RED tmp/n9nyvd-race-red.log, GREEN tmp/n9nyvd-race-green.log; jest 440, tsc 0, lint 0 errors. Headless tmp/n9nyvd-race-check.mjs/.log + tmp/n9nyvd/race-A.png, race-B.png on LU 28 as the regular review user: A first-note race: conflict shown, row kept 'Theirs first', draft kept, second Save stored 'Mine first' by 4; B edit race: conflict, row kept 'Theirs second', Cancel shows theirs; C delete race: conflict, row kept. LU 28 cleaned, LU 29 (owner's note) untouched.
