---
id: STATBUS-618
title: Units can be seen on a map from a unit, a report, a search and the region list
status: To Do
assignee: []
created_date: '2026-11-11T12:41:00Z'
labels:
  - app
  - maps
dependencies: []
priority: low
ordinal: 531204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
A statistician sees where units are, on a map, from the place they are already looking: a unit, a report, a search result, the region list. The map is built from the same data and filters as the page, and stays fast on a full national register.

## Zoom out
- 2026-11-11: PR 324 (Erik Søberg) adds `map/statistical_units.html` (commit c2ee419c7, still readable as `refs/pull/324/head`; the branch is deleted). Copy with his API key removed: [erik-statistical-units-map-pr324.html](../docs/statbus-618/erik-statistical-units-map-pr324.html). The ticket keeps the idea, not the file.
- Erik's map history (read from the code, his commits in statbus-web `charts/`, 2025-11 to 2026-11-10): `unitsonmap.html` (MapLibre clusters of a local file, 50k cap) → `fetchunitstomap.html` (same map fed from ma's REST API with a fixed filter, 10k cap, local-file fallback) → `statistical_units.html` (adds colour by a statistical variable, totals box, search, type filter; artificial data in a packed array) → PR 324's file (that last prototype moved onto the live API). Each step kept the previous one's look; the spirit is one map that answers "where are the units, and where is the weight (employees, turnover)".
- What the PR 324 map does, step by step:
  1. Reads `stat_definition_enabled` and builds one radio button per variable, so colour-by follows the instance's variables instead of the prototype's fixed employees/turnover.
  2. Reads up to 5000 `statistical_unit` rows that have coordinates (`physical_latitude`/`physical_longitude not.is.null`): `unit_type, name, stats, stats_summary, physical_postplace, primary_activity_category_path`. No time filter, no status filter, no paging: the 5000 cap is the open efficiency question.
  3. Per unit and variable takes its own value (`stats->code->value`), falling back to the aggregate (`stats_summary->code->sum`) so enterprises, which have no own value, still get one.
  4. Clusters the points (radius 40, up to zoom 13) and sums every variable inside each cluster with MapLibre `clusterProperties`; the cluster label shows the summed value of the chosen variable (k/M abbreviated) rather than a count.
  5. Colours a point by unit type (enterprise pink, legal unit blue, establishment green) and darkens it by the chosen variable, using percentile stops (0, p25, p50, p75, p95) of the loaded values so a few huge units do not wash out the scale. Clusters are coloured and sized by point count, grey when more than one type is shown.
  6. Totals box: count per shown unit type, and per variable the sum and the number of units that have a value, for what the filters leave.
  7. Unit type checkboxes (at least one stays on; legal units by default) and a name search (300 ms debounce) that re-filters and zooms to the matches.
  8. Click a cluster to zoom into it; click a point for a popup: name, type, activity path, post place, every non-zero variable.
  9. Hides country/admin border lines from the base map; OpenFreeMap tiles (no key).
- What the statbus-web prototypes have that PR 324 dropped, worth keeping:
  - `fetchunitstomap.html` asks for a point in time and a population: `valid_from`/`valid_to` around a date, `status_code=in.(act)`, a region (`physical_region_path`), ordered and paged (`limit`/`offset`), and warns when it truncates ("only the first N of M are shown"). PR 324 has none of these.
  - Its popup is richer: address, status, activity code and path, region, legal form, coordinates.
  - It says plainly when no unit has coordinates (PR 324 just shows an empty map).
  - Per-type cluster counts (`cnt_legal`, `cnt_estab` in `statistical_units.html`).
- What none of them do, and the app version must: scale to a full register (Norway 3.1M units) without shipping every point; follow the page's time frame and filters; use the logged-in session instead of a key in the file; link a point to its unit page.
- www.statbus.org prototypes, repo [statisticsnorway/statbus-web](https://github.com/statisticsnorway/statbus-web) (internal), `charts/` at master 00a333c:
  - [`unitsonmap.html`](https://github.com/statisticsnorway/statbus-web/blob/master/charts/unitsonmap.html): MapLibre clusters of units from a local file, popups, 50k cap.
  - [`fetchunitstomap.html`](https://github.com/statisticsnorway/statbus-web/blob/master/charts/fetchunitstomap.html): same map from ma's REST API with date, status and region filters and a local-file fallback.
  - [`statistical_units.html`](https://github.com/statisticsnorway/statbus-web/blob/master/charts/statistical_units.html): colour by employees/turnover, totals, search, type filter; artificial data (`statistical_units_geo.json`), MapTiler tiles.
  - [`maps_readme.txt`](https://github.com/statisticsnorway/statbus-web/blob/master/charts/maps_readme.txt): the four intended uses: all units (check lat/lon, list units missing them), a statistical-unit filter on the map ("where is the oil, where are the big companies"), links and references (all units of one group), enterprise groups and foreign units.
  - Country maps in Highcharts (`AfricaMap.html`, `newmap.html`, `statbussmap_menue.html`) are the region-count style, not unit points.
- Owner's notes, 2026-11-11 (verbatim; also in the owner's statbus-todo.md):

```
* Maps
  * https://demo.statbus.org/legal-units/9336/links
    Left side "Map" showing this unit and related units on a map.
  * https://demo.statbus.org/reports
    Left side "Map" showing counts per region like https://www.statbus.org/charts/unitsonmap.html
    with efficient implementation and drilldown.
    Use statistical_history_facet_delta to efficiently drill down.
  * From say https://demo.statbus.org/search?order=name.asc&page=1
    In addition to "Export" have a "Map" of the same list.
    Must think about efficiency?
    Possible to select some region and then see if placement is appropriate.
    Maybe only possible if less than X units, or some other way of using say
    statistical_history_facet_delta with an unit_type+unit_id filter to be efficient for grouping?
    See possibly https://www.statbus.org/charts/statistical_units.html?ver=233
    and possibly a separate quad key table with connections as you drill down.
    This used "Kartverket" API in Norway to lookup.
    Possibly a separate job to import this into statbus with only these data,
    checking that this works.
  * From https://demo.statbus.org/regions
    first add lat+lon and a button for Regions Map to see placement.
```

## Zoom in (to design with the owner in its own session, after the timeline work)
- Four places: unit links page (the unit and its related units), reports (counts per region with drilldown via statistical_history_facet_delta), search (Map beside Export, same filters), regions (lat/lon per region, then a Regions Map).
- Efficiency on a full register: aggregate (per region, per quad key tile) rather than ship every point; points only below a threshold.
- Coordinates: where they come from (import columns, a geocoding job such as Kartverket for Norway, region centroids).
- In the app, logged in by session; no API key in source. Tile provider and its terms.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Designs the map work in a session after the timeline work: which of the four places first, how coordinates are obtained, how a full register stays fast. The answer is recorded in this ticket's notes and becomes the build plan.
<!-- AC:END -->
