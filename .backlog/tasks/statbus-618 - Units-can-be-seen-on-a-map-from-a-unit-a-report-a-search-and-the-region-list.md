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
- 2026-11-11: PR 324 (Erik Søberg) adds `map/statistical_units.html`, a standalone MapLibre page that reads `/rest/statistical_unit` and `stat_definition_enabled` with an API key, with clustering, search by name, a unit type filter and colour by any statistical variable (OpenFreeMap tiles). Commit c2ee419c7 on branch `doc/api-reference`. Its API key must not be reused (see PR 324 comment); the ticket keeps the idea, not the file.
- www.statbus.org prototypes (repo statbus-web, `charts/`): `unitsonmap.html` (counts per region), `statistical_units.html` (units from `statistical_units_geo.json`, auto-fit, per-type cluster counts), `fetchunitstomap.html` (fetch from ma's REST API with a JSON fallback).
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
