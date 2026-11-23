---
id: kvbebr
title: "Location coordinates have one name in the table and the API"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zx"
created: 2026-11-18
updated: 2026-11-18
---

## Goal
A location's coordinates have one name in the location table and in what the API returns, so map code reads one name.

## Purpose
Today location has latitude/longitude while statistical_unit and the hierarchy RPC return physical_latitude/physical_longitude, so client map code must translate field names (PR https://github.com/statisticsnorway/statbus/pull/327, rsbssbno, 2026-11-14).

## Principle
A rename of a column the API exposes is a breaking change for API users and imports, so the owner decides the naming first. A migration follows the project's migration procedure: regenerated doc/db and types, updated test expectations, both directions tested.

## Relevant details
Former goal: A location's coordinates are named the same in the location table and in what the API returns, as Erik's PR #327 proposes (latitude/longitude to physical_latitude/physical_longitude), so map code reads one name.

PR #327: migration 20261114090337_rename_location_latitude_longitude (up/down) and 7 app files (general-info forms, validation, read-edit-range, hierarchy types). CI: the SQL suite FAILED, at least 10 tests: 002 ER diagram, 015 data-model doc, 016 types, 103, 104, 105, 106, 107, 109, 110; their expected outputs were not updated. The owner expects to adapt the work.

## Depends on

## Acceptance
- [x] [Owner] Decides the naming (rename as proposed, or another fix for the map code); the answer is recorded in the notes
- [ ] With the agreed change, the fast SQL suite passes with updated expected outputs, and doc/db and app types are regenerated
- [ ] Import definitions, samples and docs that name the coordinate columns use the agreed names (rg finds no old name)
- [ ] PR #327 is merged or closed on GitHub as decided, with a comment that links this task

## Notes

2026-11-21: the map plan (z2qt08, doc/design/units-on-map.md on feat/units-on-map) reads statistical_unit.physical_latitude/longitude, which exist today; the map does not wait for this rename, only the Norway coordinate load (r39dqb) does.

check 1: Owner 2026-11-23 10:46 (his boss's decision, in chat with hibiscus): the opposite of PR #327. Coordinates have one plain name everywhere: latitude, longitude, altitude. Units drop the physical_ prefix (statistical_unit.physical_latitude -> latitude, and the physical_location import step's columns likewise); regions drop center_; the postal coordinates go entirely (statistical_unit.postal_latitude/longitude/altitude and the postal_location step's coordinate columns), since a postal address needs none: location already forbids coordinates on postal rows, and 0 units carry them. PR #327 is closed as superseded. The build is jbc5bs.
