---
id: ez5thj
title: "Every page loads fast on a slow network"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzq"
created: 2026-11-27
updated: 2026-11-27
---

## Goal
Each page of the app shows its content quickly on a slow network (3G), with its first load small and its own data read only when needed.

## Purpose
Owner 2026-11-27 22:30: throttled to 3G the whole application loaded very slowly; StatBus is used in countries where slow connections are common, so the first impression on a slow line decides whether it is usable.

## Principle
Measure before changing: record what each page downloads (bytes, requests) and how long until its content shows, throttled, on the built app rather than the dev server. Cut what is not needed for the first view (load later, split, or drop); keep behaviour the same. Not before the current release (owner 2026-11-27 22:31).

## Details
Seen by jhf in Firefox on the test slot, throttled to regular 4G then 3G, while a full derive was running. The test slot runs the dev server (Turbopack), whose bundles are unminified and much larger than the built app's, so measurements must be made on the built app container. Known heavy parts loaded only where used today: MapLibre (~220 KB gzip, components/map/unit-map.tsx loads it on first use), Highcharts on the reports. The search list's own slowness on empty filters is a separate task (mafdbr).

## Depends on

## Acceptance
- [ ] A table of every top-level page (dashboard, search list and map, reports, regions, unit pages, admin) with its transferred bytes, request count and time to content on the built app, throttled to 3G, recorded before and after
- [ ] Each page shows its content within an agreed budget on 3G, measured with the same method
- [ ] ~~A check in CI or a recorded benchmark script that reports each page's first-load bytes, so a regression is seen~~ (not relevant: one job per check: rewritten as check 4, hibiscus, 2026-11-27)
- [ ] A recorded benchmark script reports each page's first-load bytes and time on the built app, run before and after, so a regression is seen
- [ ] [Owner] Sets the 3G time-to-content budget per page, recorded in Notes; the budget measurement compares against it, and a page over budget gets a fix before the task closes

## Notes

2026-11-27 22:31 owner: on the maps the remote base tiles (OpenFreeMap: style, fonts, vector tiles) will weigh more than our own results; measure them separately per map page. Serving the tiles from the installation is task a9168x.
