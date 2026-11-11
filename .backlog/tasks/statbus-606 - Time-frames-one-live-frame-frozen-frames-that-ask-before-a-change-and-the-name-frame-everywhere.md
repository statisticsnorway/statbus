---
id: STATBUS-606
title: >-
  Time frames: one live frame, frozen frames that ask before a change, and the
  name frame everywhere
status: In Progress
assignee: []
created_date: '2026-11-10T16:55:00Z'
updated_date: '2026-11-11T14:18:00Z'
labels:
  - ui
  - time
  - design
dependencies: []
priority: high
type: feature
ordinal: 520204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Zoom out
Statisticians think in time frames: one live frame that takes every new import and edit, and the years before it, which change only on purpose. Ville (Statistics Finland) works with frozen frames; StatBus stores timelines, and a time frame is the window a user looks through. Today that window is called "time context" and its list was built as a hedge (owner, 2026-11-10): public.relative_period has 26 period kinds of which 3 are enabled (year_curr, year_prev, year_prev_only), each with a query name, an input name and a scope (query, input, both); public.time_context unions those with tags carrying context dates (0 on every box) and one entry per year with data ("2024 (Data)"). Import jobs reference it as import_job.time_context_ident: r_year_curr on et 13, ma 4, ug 2, demo 1; r_year_prev on demo 6; none elsewhere. A cloned job keeps the ident and re-derives its dates (public.import_job_clone), so a relative ident is what a recurring job needs.

## Zoom in
Decided by the owner 2026-11-10 (details in the notes):
- Three kinds of frame, one list everywhere:
  - Live frame (kind live, ident `live`): "Live frame (2026)", 1 January of the current year to infinity, read as of today. Changes go straight in.
  - Relative frame (kind relative, ident `prev`): "Previous frame (2025)", 1 January to 31 December of the previous year, read as of 31 December. Moves on 1 January.
  - Fixed frame (kind fixed, ident `y_YYYY`): "Frame 2024", one closed year forever; every year with data, and the previous year.
- The menu lists live, relative, then fixed frames, leaving out a fixed frame that equals a relative one (Frame 2025 today). The import page shows all three groups in full, so a recurring job picks Previous frame and a one-off picks Frame 2025.
- Relative and fixed frames ask before a change reaches into them: "fixed frame" wording, UI only, no database enforcement. A real frozen frame (a stored copy of statistical_unit rows) is not in scope.
- One migration renames time_context to time_frame everywhere (view, kind type, import_job.time_frame_ident, the valid_time_from mode, the definition_snapshot key, admin.import_job_derive, public.import_job_clone, admin.apply_rls_to_all_tables, comments), drops relative_period, relative_period_with_time, the scope split, the second name and tag frames, and maps job idents r_year_curr -> live, r_year_prev -> prev; jobs keep their stored dates.
- The app, CLI, tests, samples and docs follow; no old name remains.
- The edit form and the import pages show a Frame dropdown defaulting to the selected frame; an edit icon opens the details (Data Source, Valid From, Valid To; on import pages the other options, including Source dates).
- Each step is shown to the owner in Firefox before it lands.
- Later, not here: a custom date picker below the frames; a timeline in the edit when a change needs thought.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Tries the frame selector, the edit form and an import page on a local branch in Firefox and approves the wording and layout. The answer is recorded in this ticket's notes: approval lets the step land; requested changes are made on the branch and shown again.
- [ ] #2 Test 399 asserts public.time_frame for a fixed app.current_date: the live frame (live, 1 Jan current year .. infinity, read as of that date), the relative frame (prev, previous year 1 Jan .. 31 Dec), fixed frames y_YYYY for the previous year and every year with data, each with its kind and the relative frame it equals; and again for a date in the next year, where live and prev have moved and the fixed frames have not (RED before the migration, GREEN after)
- [ ] #3 One migration renames time_context to time_frame everywhere and drops relative_period, relative_period_with_time, the scope and second name and tag frames; after it, rg -i 'time_context|relative_period|timecontext' over app/src, cli, test/sql, samples, doc (outside doc/db history) and the live schema finds nothing; existing jobs on r_year_curr and r_year_prev carry live and prev with their stored dates unchanged; the fast suite passes and doc/db and types are regenerated
- [ ] #4 The frame menu lists Live frame, Previous frame and the fixed frames that do not equal a relative frame, in that order; an import page lists all three groups; a test of the app's frame list asserts both
- [ ] #5 The edit form opens on a Frame dropdown with the selected frame; the edit icon shows Data Source, Valid From and Valid To and returns to the frame; a test saves an edit in the live frame and one in a fixed frame and asserts the stored rows
- [ ] #6 The three import pages show Frame with the selected frame as default and the edit icon reveals the other options including Source dates; an import job created from each page carries the chosen frame ident
- [ ] #7 An edit or import in the UI that reaches into a relative or fixed frame asks first, naming the frames it touches; cancelling stores nothing; confirming stores the change. Only the UI asks: API, CLI and scheduled jobs run unattended (owner 2026-11-11)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-10 17:02: the confirmation is UI only. The aim is a simpler UI: fewer things to show and think about, and the defaults just work. Later, at the end of this ticket or in its own: when an edit is likely to need thought (found by heuristics), show the field's timeline in the edit, so the user sees when the value changed and how long the change lasts. Designed together with the owner as UX/interaction work, not specified up front.

Owner 2026-11-10 21:02: names reviewed all the way through, database included. 'Live frame YYYY' = [1 Jan of the current year, infinity): 'live' means until further notice. 'Frame YYYY' = 1 Jan .. 31 Dec of that year (closed). These frames are not called frozen in the product, because changes to them are not tracked; they are 'frozen' only in the light sense that the UI asks before an edit or import reaches into them. A real frozen frame would be a stored copy (snapshot) of the frame's statistical_unit rows with a predictable name (frozen_frame), possibly later; time_frame is the view into statistical_unit we have now. Sizing on the full Norway register (local): one frame is 3.12M of 3.14M statistical_unit rows, 85 columns, 6.1 GB, so a copy costs about the table's size per frozen year.

Owner 2026-11-10 21:36: approved the cleanup. One list everywhere: Live frame YYYY (ident live, [1 Jan current year, infinity), read as of today) and Frame YYYY (ident y_YYYY, 1 Jan..31 Dec, read as of 31 Dec) for the previous year always and every earlier year with data. Removed: relative_period and its 23 unused codes, the query/input scope and second name, tags as frames (0 on every box). time_context renamed time_frame everywhere in one migration. Import jobs keep their stored dates; ident mapping r_year_curr -> live, r_year_prev -> y_<previous year> (demo 6 jobs). The owner hedged the original list because the need was unknown; frames are what users need. Later, possibly: a custom date picker below the frames as the escape hatch to look at any date (not in this ticket).

Owner 2026-11-10 21:37-21:45, revising the list: relative and fixed frames are different things and are named apart. Relative: Live frame (ident live, 1 Jan current year .. infinity, read as of today) and Previous frame (ident prev, 1 Jan .. 31 Dec of the previous year, read as of 31 Dec: it ends like a fixed frame). Fixed: Frame YYYY (ident y_YYYY, that year forever). Relative idents are what recurring import jobs need: import_job_clone keeps the ident and re-derives the dates, so a job on prev loads last year every year. The time_frame view carries kind (relative/fixed) and, for a fixed frame, which relative frame it currently equals. The menu hides a fixed frame that equals a relative one (Live, Previous, Frame 2024, ...); the import page shows all, grouped 'Moves with the calendar' / 'Fixed year'. Ident mapping: r_year_curr -> live, r_year_prev -> prev (supersedes y_<previous year>).

Owner 2026-11-10 21:46: the word is 'fixed frame', not 'frozen frame'. Fixed frames are Frame YYYY (that year forever); relative frames are Live frame and Previous frame. The confirmation before a change reaches into a past year says fixed frame.

Owner 2026-11-10 21:46-21:47: three kinds of frame. Live frame (kind live: Live frame YYYY, current year onwards, open-ended, changes go straight in). Relative frame (kind relative: Previous frame YYYY, one closed year named by its position, moves on 1 January). Fixed frame (kind fixed: Frame YYYY, one closed year named by its number, never moves). Relative and fixed frames ask before a change. The time_frame view carries kind in (live, relative, fixed); the menu lists live, relative, then fixed frames, leaving out a fixed frame that equals a relative one; the import page shows all three groups in full.

21:49 RED: test 399 (test/sql/399_statbus_606_time_frames.sql, 98bb66402) fails on master with 'relation public.time_frame does not exist'. Next: the time_frame migration.

Owner 2026-11-10 23:16 (passing by the screenshots): likes what he sees; asked for a small info icon next to Live frame, Relative frames and Fixed frames explaining the concept. Done in f077e315d: one explanation per kind in TIME_FRAME_GROUPS (app/src/lib/time-frame.ts), shown by TimeFrameGroupHeading in the menu, the import list and the command palette. Night 22:05-22:18 progress on branch statbus-606-time-frames (not pushed): app 0d00d31de, docs 93171e821, tests+samples 44351e8f5 (19/20 pass, 404 only the known STATBUS-558 analytics line), palette ed616f171, 015/302 fcfa0c754, doc/db 9d272adb7, leftovers 35bf4b8ae. rg over app/src, cli, test/sql, samples, doc (outside doc/db and the dated audit/security snapshots) and the live schema finds no old name. tsc 0, lint 0 errors, jest 248/248. Review screenshots + README in tmp/606-review/ (script tmp/606-review-shots.mjs).

Night 22:18-22:52: edit form (d70088ad7) opens on Frame = selected frame; choosing a frame re-derives the dates by the 604 rule (editPeriodInFrame, jest); pencil shows Data Source/Valid From/Valid To, 'Back to frame' returns. Import pages (7673efb03) open on Frame; pencil reveals the other options incl. Source Dates; jobs from legal-units/establishments/establishments-without-legal-unit carry the chosen ident (prev, 2025 dates; tmp/606-review/import-jobs.json). Confirmation (0763a80c6): framesNeedingConfirmation + useFixedFrameConfirmation; real app on FRAME REVIEW AS (6060606060, from 2023): prev Save asks 'Previous frame (2025)', Cancel stores nothing, Confirm stores 2025 only; Frame 2024 asks 'Frame 2024'; live saves without asking; import Continue on Frame 2024 asks, Cancel no job, Confirm job y_2024 (tmp/606-review/confirm-*.json). Fast suite 139/139 (tmp/test-606-fast-2.log), jest 255/255, tsc 0, lint 0 errors. Open for owner: AC#7 'allow changes to fixed frames' setting (UI-only question means API/CLI jobs are never asked) and the wording questions in tmp/606-review/README.md. Local housekeeping: rejected stale local demo jobs 7-9 (waiting_for_review since 16:57, blocking the queue); job 10 failed as a consequence.

Owner 2026-11-11 11:51: AC#7 decided as 'only the UI asks'; no 'allow changes to fixed frames' job setting (it would matter only if the database refused changes to past frames, a separate ticket). The criterion was rewritten and is now the last one. Review 11:44-11:49: upload pages show the one-line job summary (010bf6e8e), approved; edit form on FRAME REVIEW AS approved, confirmation worked, rename saved to Previous frame (2025) only. Found: the edit's Data source starts empty, so the rename stored data_source_id NULL for 2025 (was 2). Owner: default Data source and Comment to the values already there, so doing nothing preserves them, and allow clearing both. Fix next, before the merge of master.

2026-11-11 14:05: in release candidate v2026.11.4-rc.02 (49376c40a; CI all green, ./sb release check green). Release tests held up by outside outages (Hetzner core limit, then Canonical snap store); re-run when the store answers. Remaining owner checks after the release reaches a box.
<!-- SECTION:NOTES:END -->
