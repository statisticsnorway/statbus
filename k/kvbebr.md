---
id: kvbebr
title: "Location coordinates have one name in the table and the API"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zx"
created: 2026-11-18
updated: 2026-11-18
doing_since: "2026-11-26T21:50"
doing_with: "jbc5bs"
stage: "waiting"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_b"
waiting_on: "Hibiscus implements the rename with jbc5bs"
waiting_since: "2026-11-27T01:12"
waiting_asked_by: "rabbit"
---

## Goal
Coordinates have one plain name, latitude, longitude, altitude, in location, units and regions; postal addresses carry none.

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
- [x] With the agreed change, the fast SQL suite passes with updated expected outputs, and doc/db and app types are regenerated
- [x] Import definitions, samples and docs that name the coordinate columns use the agreed names (rg finds no old name)
- [x] PR #327 is merged or closed on GitHub as decided, with a comment that links this task

## Requests
- 2026-11-27T11:06 request 1 by jhf:
  Hibiscus, didn't you merge this work from aux? Why isn't this checked off?

## Notes

2026-11-21: the map plan (z2qt08, doc/design/units-on-map.md on feat/units-on-map) reads statistical_unit.physical_latitude/longitude, which exist today; the map does not wait for this rename, only the Norway coordinate load (r39dqb) does.

check 1: Owner 2026-11-23 10:46 (his boss's decision, in chat with hibiscus): the opposite of PR #327. Coordinates have one plain name everywhere: latitude, longitude, altitude. Units drop the physical_ prefix (statistical_unit.physical_latitude -> latitude, and the physical_location import step's columns likewise); regions drop center_; the postal coordinates go entirely (statistical_unit.postal_latitude/longitude/altitude and the postal_location step's coordinate columns), since a postal address needs none: location already forbids coordinates on postal rows, and 0 units carry them. PR #327 is closed as superseded. The build is jbc5bs.

2026-11-23 10:48 the build is in jbc5bs (this task's decision applied to regions and units together); PR #327 is to be closed as superseded with a comment linking both tasks, once jbc5bs lands.

2026-11-23 10:49 correction to check 1's wording: the decision MEETS PR #327's aim (one name for a coordinate, so map code reads one field without translating) the other way round. #327 adds physical_ to location to match statistical_unit; the owner's decision drops the prefixes so all say latitude, longitude, altitude, and with postal coordinates gone there is nothing left for physical_ to tell apart. The closing comment on #327 says so.

Correction 2026-11-26 (owner): Erik's comment on PR #327 (2026-11-14) asked only that rpc/statistical_unit_hierarchy and statistical_unit return the SAME names for latitude/longitude, for one generic map. His agent turned that into renaming location to physical_latitude, the opposite of the owner's choice. Owner: physical_ was there only because postal locations were systematically given a position too; StatBus records no position for a postal address (location rows carry coordinates only for type physical), so physical_ says nothing and goes. jbc5bs delivers Erik's wish: statistical_unit becomes latitude/longitude/altitude, matching location and the hierarchy RPC. PR #327 to be closed with a reply saying so, the reply approved by the owner first.

check 4: PR #327 closed 2026-11-26 with the owner-approved reply (tmp/pr327-reply.md): Erik's wish is met by jbc5bs, plain latitude/longitude/altitude everywhere.


check 2: Shipped with jbc5bs, commit 3bf2dbc6f on feat/coordinates-named-latitude: fast suite All 146 tests passed, doc/db and app types regenerated
check 3: Same commit: import definitions (source/data columns), samples/demo script, app/public/demo CSVs, test data, data-model.md, import-system.md, api-reference.md renamed; rg finds old names only in the refusal code and its tests
## History
- 2026-11-26T21:50 todo -> doing/active (take with jbc5bs)
- 2026-11-27T00:18 handed to rabbit: ox's session ended (closed 2026-11-26 23:16)
- 2026-11-27T01:12 doing/active -> doing/waiting (wait)
- 2026-11-27T11:06 request 1 by jhf
