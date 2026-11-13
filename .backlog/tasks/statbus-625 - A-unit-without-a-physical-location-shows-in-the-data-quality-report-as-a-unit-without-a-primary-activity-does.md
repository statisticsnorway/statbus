---
id: STATBUS-625
title: >-
  A unit without a physical location shows in the data-quality report, as a unit
  without a primary activity does
status: To Do
assignee: []
created_date: '2026-11-13T13:52:00Z'
labels:
  - data-quality
dependencies: []
priority: high
ordinal: 537204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-13 13:36: the physical location stays removable (STATBUS-611), and it is important that a legal unit or establishment left without one, for any part of its existence, shows up in the data-quality report the way a missing primary activity does.

Today the dashboard's Data quality section has Units Missing Region and Units Missing Activity Category, each counting units that exist at the selected time frame's date (lib/unit-existence.ts) and linking to the matching search. A location's country is NOT NULL, so a unit has a physical location exactly when statistical_unit.physical_country_id is set.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Data quality section has a Units Missing Physical Location card counting legal units and establishments existing at the selected frame's date with no physical location
- [ ] #2 The card links to the Statistical Units search listing exactly those units
- [ ] #3 A unit whose physical location is removed for part of its life is counted in the frames covering that part, and not in the others (test on a local unit)
<!-- AC:END -->
