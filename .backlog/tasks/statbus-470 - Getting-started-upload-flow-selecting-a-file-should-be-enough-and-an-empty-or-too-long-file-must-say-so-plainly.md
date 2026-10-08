---
id: STATBUS-470
title: >-
  Getting-started upload flow: selecting a file should be enough, and an empty
  or too-long file must say so plainly
status: To Do
assignee: []
created_date: '2026-10-08 12:30'
labels:
  - app
  - import
  - devx
dependencies: []
priority: high
ordinal: 396204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: choosing a file and pressing upload is enough, and a bad file says plainly what is wrong with it.

FIELD REPORT (Ville, 2026-10-08, screenshot). Importing an ActivityCategories CSV: after selecting the file he pressed Upload and got 'Failed to upload file: Could not find the ActivityCategoryLevel column of activity_category_enabled_custom in the schema cache'. Pressing Upload again surfaced the next hurdle, 'varchar is set to 256, at least 1 of my lines is too long'. His own correction of the first: he needed to press Upload after selecting the file, which implies the first attempt ran with no file actually selected and produced a nonsensical schema-cache error rather than saying 'no file selected'.

OWNER DIRECTIVE.
1. Selecting a file should be sufficient. Confirming the upload must use the selected file instead of requiring a second button press, and the same pattern must hold across the getting-started and bootstrap steps so this class of error cannot happen at all.
2. An empty file, or no file selected, must produce a sensible message that says exactly that, never a schema-cache or varchar error.
3. A value that is too long must name the offending row, the column and the limit, so the operator can fix the file without guessing.

PREREQUISITE AND TIMING (owner): reproduce locally once the local database is ready, after the other work in flight. The local DB currently holds the restored February Norway dump, so this flow needs a working install or seed first.

SCOPE: the upload UX in the getting-started/bootstrap steps, from file selection through upload confirmation, and the messages those steps produce. Not the import pipeline's validation semantics beyond those messages.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With a file selected, confirming the upload uses that file; no second button press is needed. Verified on the local reproduction.
- [ ] #2 An empty file, or no file selected, produces a specific sensible message naming what is wrong, never a schema-cache or varchar error.
- [ ] #3 A value exceeding the column limit names the offending row, column and limit.
- [ ] #4 The same select-then-upload behaviour holds across the getting-started steps, verified in at least two of them.
- [ ] #5 Reproduced and verified against a ready local database, with the before and after messages recorded.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The observed before and after messages, and the step where each occurred, are recorded in the ticket.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner report 2026-10-08 from the Finland getting-started run. Timing: do this after the in-flight work and once the local database is ready to reproduce the flow; it is scheduled, not forgotten.
<!-- SECTION:NOTES:END -->
