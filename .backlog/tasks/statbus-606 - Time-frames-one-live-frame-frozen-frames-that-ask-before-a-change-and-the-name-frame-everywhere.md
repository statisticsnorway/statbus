---
id: STATBUS-606
title: >-
  Time frames: one live frame, frozen frames that ask before a change, and the
  name frame everywhere
status: In Progress
assignee: []
created_date: '2026-11-10T16:55:00Z'
updated_date: '2026-11-10T21:36:00Z'
labels:
  - ui
  - time
  - design
dependencies: []
priority: high
ordinal: 520204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
A statistician thinks in **time frames**: one **live frame** that takes every new import and edit, and **frozen frames** for the years before it, which change only on purpose. StatBus stores timelines, and a time frame is the window a user looks through. The word "frame" is used everywhere: in the UI, the API, the database and the code. Statisticians coming from a frozen-frame register (Ville, Statistics Finland) recognise the model and are not shown options that rarely apply to them.

## Model (owner, 2026-11-10)
- **Time frame** is the concept. Today it is called "time context" (`public.time_context`, `time_context_type`, `import_job.time_context_ident`, the app's `timeContext` atoms and the `tcc` URL parameter).
- **Live frame**: the current year onwards (today "Current Year (2026)", 2026-01-01..infinity, read as of today). Edits and imports go straight in.
- **Frozen frames**: every frame before the live frame ("Frame 2025", "Frame 2024", ...; read as of 31 December). "Frozen" means one thing only: a change that reaches into a frozen frame asks for a separate confirmation. Nothing is locked, and corrections stay possible.
- A frame freezes by itself on 1 January, when the next year's live frame starts.

## Changes
1. **Rename, one systematic migration.** `time_context` becomes `time_frame` throughout: the view, the type `time_context_type` -> `time_frame_type`, the column `import_job.time_context_ident` -> `time_frame_ident`, the functions that read them (`import_job_derive`, `import_job_clone`), comments, regenerated `doc/db` and types, the app (atoms, components, the URL parameter), the CLI, and the docs. One canonical name, no aliases left behind.
2. **Names in the UI.** "Select time" -> "Select time frame"; "Current Year (2026)" -> "Live frame (2026)"; the year entries -> "Frame 2025", ... grouped as frozen frames. "Previous Year (2025)" and "2025 (Data)" show the same view today (as of 2025-12-31) and become one entry.
3. **Edit form.** The edit shows a Frame dropdown, defaulting to the selected frame. An edit icon opens the details (Data Source, Valid From, Valid To), with a way back to the frame. Within the chosen frame the edit covers the stretch where the shown value is valid (STATBUS-604); the details show the exact dates it uses, and how the database clips them to where the unit exists (the definition of an update for portion of).
4. **Import pages** (`/import/legal-units`, `/import/establishments`, `/import/establishments-without-legal-unit`). "Data Validity Period" becomes "Frame": a dropdown defaulting to the selected frame, and an edit icon that opens the other options, including "Source dates".
5. **Frozen-frame confirmation.** Any edit or import whose period starts before the live frame asks first, naming the frames it touches ("This change reaches into Frame 2024 and Frame 2025, which are frozen. Change them anyway?"). Unattended imports (rune's monthly BRREG run) set "allow changes to frozen frames" when the job is created; the import page asks the same confirmation when it is set.

## Approach
Explore the UI first: build the frame selector, edit form and import page on a local branch, try it in Firefox with the owner, and settle the wording and layout there before the rename migration lands.

## Out of scope (later tickets)
- Enforcing the confirmation in the database, so that a direct API write into a frozen frame fails unless it confirms.
- Truly frozen frames: saved snapshots that never change, for publication.
- The timeline editor.
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
<!-- SECTION:NOTES:END -->
