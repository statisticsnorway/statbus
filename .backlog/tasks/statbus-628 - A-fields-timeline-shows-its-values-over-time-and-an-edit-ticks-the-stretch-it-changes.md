---
id: STATBUS-628
title: >-
  A field's timeline shows its values over time, and an edit ticks the stretch
  it changes
status: In Progress
assignee: []
created_date: '2026-11-12T15:15:00Z'
updated_date: '2026-11-12T15:16:00Z'
labels:
  - app
  - edit
dependencies: []
ordinal: 539204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Each field on a unit's page shows how its value changed over time, and an edit changes exactly the stretch of that history the user ticks.

### Zoom out
The edit form's Simple and Advanced views change one time frame or chosen dates. A user who sees one value cannot tell which other values the field had, or what an edit will overwrite. The timeline shows the field's history, laid out by time frame, and is a third way to say where an edit applies.

### Zoom in
- A timeline icon beside each field's (i) opens a popover: frames on the left (Live 2026, Previous 2025, fixed years), a line with one dot per value, values on the right with dates and data source. The value the page shows has a filled dot. An X closes it.
- Edit gets a Timeline view beside Simple and Advanced, with a checkbox per value. The ticked values form one unbroken stretch, and the edit's dates are that stretch. Simple, Advanced and Timeline read the same dates, so they stay in step.
- Edit opens in Timeline when the frame holds more than one value of the field, and in Simple when one value covers it.
- A frame with more than 3 values folds to 2 (the shown, ticked, newest, oldest). The fold's control sits on the right edge; opened, a bracket spans exactly the values that came out, with the same chevron to fold them back. Show all, bottom right, opens or folds every frame.
- The popover opens on the side with more room and never runs off the window; the values scroll inside it.

Owner design and approval in the 2026-11-11 and 2026-11-12 Firefox reviews on units 26-28 (TIMELINE REVIEW AS, TIMELINE MANY AS, TIMELINE CROWDED AS).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The timeline icon beside a field opens its values over time, by frame, with the shown value marked
- [x] #2 Edit offers a Timeline view; ticking values sets the edit's dates to exactly that stretch, and Simple, Advanced and Timeline agree
- [x] #3 Edit opens in Timeline when the frame holds more than one value of the field
- [x] #4 A crowded frame folds to two values; opening shows a bracket over exactly the opened values, and its chevron folds them back in place
- [x] #5 The popover opens in the same place on every click, stays inside the window, and keeps its X and Show all visible
- [x] #6 Saving from the Timeline view changes only the ticked stretch (checked in the database)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-12 15:16 committed 2b96b8f61 (timeline model: fieldTimeline, frameSegments, visibleSegments, unfoldedRuns, rowSelected, frameMarker; 26 jest cases), d5d4d9ea4 (icon + popover view), ab07e938c (edit's Timeline view). RED/GREEN for each owner round in statbus_test/tmp: timeline-v1-*-red/green.log, timeline-bracket-{red,green}.log, timeline-foldsel-{red,green}.log, timeline-marker-{red,green}.log, timeline-v1-popover-{red,green}.log (popover placement reproduced: firstShowAllVisible, sameSideBothClicks, expandedShowFewerVisible false -> true). Real app on unit 28 headless: tmp/timeline-v1-bracket.log, tmp/timeline-v1-anchor.log PASS. On origin/master 7369edaee + these commits: jest 308/308, tsc 0, lint 0 errors (tmp/628-worktree-checks.log). Owner in Firefox 14:43-14:51: Live-only save, ticked 2026-01..present, back-in-time 2023 with the fixed-frame warning, each checked in the database (tmp/timeline-v1-save-after{,2,3}.log); unit 28 restored by re-import, same 25 rows. Owner 15:13: timeline viewer approved.
<!-- SECTION:NOTES:END -->
