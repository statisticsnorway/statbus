---
id: z9gggq
title: "Reports Map: zooming in and out changes the region level"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzv"
created: 2026-11-28
updated: 2026-11-28
---

## Goal
On Reports → Map, zooming in past a level goes into the region at the view's centre and zooming out goes back up.

## Purpose
Owner 2026-11-28 13:50: tried on the Reports Map 2026-11-27; it works but is not fully predictable as you zoom in, and the first release of the map should be minimal and sensible, with polish after.

## Principle
Build on the released Reports Map (ppvxg2). Only the user's own zooms change the level (the map's own framing never does), and a step made by zooming keeps the view where the user put it. Tried on this map first; ported to other maps only if it proves itself.

## Details
The prototype was on the Reports Map 2026-11-27 (switch 'Zoom changes the level', off by default): levelForZoom (country below zoom 6, one level per 1.5 zoom steps), user zooms detected by the zoomend event's originalEvent, fits clamped into the level's zoom band. The code is in branch explore/ppvxg2-spider-and-side-box (commit 99b61e5c2, app/src/app/reports/map/page.tsx: levelForZoom, zoomBand, ReportsMap:zoomDrives). Owner's finding: works, but not fully predictable as you zoom in.

## Depends on

## Acceptance
- [ ] Zooming in over a county on the Reports Map goes into the county nearest the view's centre, and zooming out goes back up, seen in Firefox
- [ ] Framing a new level never changes the level by itself, seen by stepping in and out three levels in Firefox
- [ ] [Owner] Decides from trying it whether it becomes the Reports Map's behaviour, recorded in Notes: yes ships it, no drops this task

## Notes
