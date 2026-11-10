---
id: STATBUS-606
title: >-
  Time frames: one live frame, frozen frames that ask before a change, and the
  name frame everywhere
status: In Progress
assignee: []
created_date: '2026-11-10T16:55:00Z'
updated_date: '2026-11-10T21:45:00Z'
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
Statisticians think in time frames: one live frame that takes every new import and edit, and the years before it, which change only on purpose. Ville (Statistics Finland) works with frozen frames; StatBus stores timelines, and a time frame is the window a user looks through. Today that window is called "time context" and its list was built as a hedge (owner, 2026-11-10): public.relative_period has 26 period kinds of which 3 are enabled (year_curr, year_prev, year_prev_only), each with a query name and an input name and a scope (query, input, both); public.time_context unions those with tags carrying context dates (0 on every box) and one entry per year with data ("2024 (Data)"). Import jobs reference it as import_job.time_context_ident: r_year_curr on et 13, ma 4, ug 2, demo 1; r_year_prev on demo 6; none elsewhere.

## Zoom in
Approved by the owner 2026-11-10 (notes):
- One list everywhere, menu, edit form and import page alike:
  - Live frame YYYY, ident `live`: 1 January of the current year to infinity, read as of today. "Live" means until further notice; the ident stays across New Year.
  - Frame YYYY, ident `y_YYYY`: 1 January to 31 December, read as of 31 December; the previous year always, and every earlier year with data.
- These frames are frozen only in the light sense: the UI asks before an edit or import reaches before the live frame (UI only; no database enforcement). A real frozen frame (a stored copy of the frame's statistical_unit rows) is not in scope.
- One migration renames time_context to time_frame everywhere (view, type, import_job.time_frame_ident, admin.import_job_derive, public.import_job_clone, comments), drops relative_period, relative_period_with_time, the scope split, the second name and tag frames, and maps existing job idents: r_year_curr -> live, r_year_prev -> y_<previous year>; jobs keep their stored dates.
- The app, CLI, tests, samples and docs follow; no old name remains.
- The edit form and the import pages show a Frame dropdown defaulting to the selected frame; an edit icon opens the details (Data Source, Valid From, Valid To; on import pages the other options, including Source dates).
- Explored with the owner in Firefox before each step lands.
- Later, not here: a custom date picker below the frames to look at any date; a timeline in the edit when a change needs thought.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Tries the frame selector, edit form and import page on a local branch in Firefox and approves the wording and layout. The answer is recorded in this ticket's notes: approval starts the rename migration; requested changes are made on the branch and shown again.
- [ ] #2 One migration renames time_context to time_frame everywhere (view, type, import_job column, functions, comments); after it, rg -i 'time_context|timecontext' over migrations' current definitions, doc/db, app/src, cli and doc finds only the migration's own history; fast tests pass and doc/db and types are regenerated
- [ ] #3 The frame selector reads 'Select time frame' and lists 'Live frame (<year>)' and the frozen frames 'Frame <year>', with no year listed twice
- [ ] #4 The edit form opens on the Frame dropdown with the selected frame; the edit icon shows Data Source, Valid From and Valid To and returns to the frame; a test saves an edit in the live frame and one in a frozen frame and asserts the stored rows
- [ ] #5 The three import pages show 'Frame' with the selected frame as default and the edit icon reveals the other options including Source dates; an import job created from each page carries the chosen frame
- [ ] #6 An edit or import that starts before the live frame shows the confirmation naming the frozen frames it touches; cancelling stores nothing; confirming stores the change; an import job created with 'allow changes to frozen frames' runs unattended
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-10 17:02: the confirmation is UI only. The aim is a simpler UI: fewer things to show and think about, and the defaults just work. Later, at the end of this ticket or in its own: when an edit is likely to need thought (found by heuristics), show the field's timeline in the edit, so the user sees when the value changed and how long the change lasts. Designed together with the owner as UX/interaction work, not specified up front.

Owner 2026-11-10 21:02: names reviewed all the way through, database included. 'Live frame YYYY' = [1 Jan of the current year, infinity): 'live' means until further notice. 'Frame YYYY' = 1 Jan .. 31 Dec of that year (closed). These frames are not called frozen in the product, because changes to them are not tracked; they are 'frozen' only in the light sense that the UI asks before an edit or import reaches into them. A real frozen frame would be a stored copy (snapshot) of the frame's statistical_unit rows with a predictable name (frozen_frame), possibly later; time_frame is the view into statistical_unit we have now. Sizing on the full Norway register (local): one frame is 3.12M of 3.14M statistical_unit rows, 85 columns, 6.1 GB, so a copy costs about the table's size per frozen year.

Owner 2026-11-10 21:36: approved the cleanup. One list everywhere: Live frame YYYY (ident live, [1 Jan current year, infinity), read as of today) and Frame YYYY (ident y_YYYY, 1 Jan..31 Dec, read as of 31 Dec) for the previous year always and every earlier year with data. Removed: relative_period and its 23 unused codes, the query/input scope and second name, tags as frames (0 on every box). time_context renamed time_frame everywhere in one migration. Import jobs keep their stored dates; ident mapping r_year_curr -> live, r_year_prev -> y_<previous year> (demo 6 jobs). The owner hedged the original list because the need was unknown; frames are what users need. Later, possibly: a custom date picker below the frames as the escape hatch to look at any date (not in this ticket).

Owner 2026-11-10 21:37-21:45, revising the list: relative and fixed frames are different things and are named apart. Relative: Live frame (ident live, 1 Jan current year .. infinity, read as of today) and Previous frame (ident prev, 1 Jan .. 31 Dec of the previous year, read as of 31 Dec: it ends like a fixed frame). Fixed: Frame YYYY (ident y_YYYY, that year forever). Relative idents are what recurring import jobs need: import_job_clone keeps the ident and re-derives the dates, so a job on prev loads last year every year. The time_frame view carries kind (relative/fixed) and, for a fixed frame, which relative frame it currently equals. The menu hides a fixed frame that equals a relative one (Live, Previous, Frame 2024, ...); the import page shows all, grouped 'Moves with the calendar' / 'Fixed year'. Ident mapping: r_year_curr -> live, r_year_prev -> prev (supersedes y_<previous year>).
<!-- SECTION:NOTES:END -->
