---
id: kvbebr
title: "Location coordinates have one name in the table and the API"
state: "done"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zx"
created: 2026-11-18
updated: 2026-11-18
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_b"
done_at: "2026-11-27T14:44"
---

## Goal
Coordinates have one plain name, latitude, longitude, altitude, in location, units and regions; postal addresses carry none.

## Purpose
Today location has latitude/longitude while statistical_unit and the hierarchy RPC return physical_latitude/physical_longitude, so client map code must translate field names (PR https://github.com/statisticsnorway/statbus/pull/327, rsbssbno, 2026-11-14).

## Principle
A rename of a column the API exposes is a breaking change for API users and imports, so the owner decides the naming first. A migration follows the project's migration procedure: regenerated doc/db and types, updated test expectations, both directions tested.

## Relevant details
PR #327 (Erik, 2026-11-14) proposed the opposite direction (location to physical_latitude); it is closed as superseded by jbc5bs, which gives every table and the API the plain names latitude, longitude, altitude and drops postal coordinates. Shipped on master b534af8e5 (2026-11-27). The owner's hard cut means no code names the old headers anywhere, so check 3's sweep finds them only in migrations and in tests that show an old header meeting the ordinary unknown-column handling.

## Depends on

## Acceptance
- [x] [Owner] Decides the naming (rename as proposed, or another fix for the map code); the answer is recorded in the notes
- [x] With the agreed change, the fast SQL suite passes with updated expected outputs, and doc/db and app types are regenerated
- [x] Import definitions, samples and docs that name the coordinate columns use the agreed names (rg finds no old name)
- [x] PR #327 is merged or closed on GitHub as decided, with a comment that links this task

## Requests
- 2026-11-27T11:06 request 1 by jhf:
  Hibiscus, didn't you merge this work from aux? Why isn't this checked off?
  resolved 2026-11-27T13:41 by hibiscus:
    Its checks are all ticked, but the work was on ox's branch, never merged: feat/units-on-map had to land first. Today (12:20) feat/units-on-map went to master (c3726cdc2); then hibiscus rebased the rename onto it, applied your hard cut and renamed the map code too: b534af8e5 on feat/coordinates-named-latitude. CI Fast Tests 46000665092 is running; when green it fast-forwards master and kvbebr and jbc5bs are closed with that commit.

## Notes

2026-11-21: the map plan (z2qt08, doc/design/units-on-map.md on feat/units-on-map) reads statistical_unit.physical_latitude/longitude, which exist today; the map does not wait for this rename, only the Norway coordinate load (r39dqb) does.

check 1: Owner 2026-11-23 10:46 (his boss's decision, in chat with hibiscus): the opposite of PR #327. Coordinates have one plain name everywhere: latitude, longitude, altitude. Units drop the physical_ prefix (statistical_unit.physical_latitude -> latitude, and the physical_location import step's columns likewise); regions drop center_; the postal coordinates go entirely (statistical_unit.postal_latitude/longitude/altitude and the postal_location step's coordinate columns), since a postal address needs none: location already forbids coordinates on postal rows, and 0 units carry them. PR #327 is closed as superseded. The build is jbc5bs.

2026-11-23 10:48 the build is in jbc5bs (this task's decision applied to regions and units together); PR #327 is to be closed as superseded with a comment linking both tasks, once jbc5bs lands.

2026-11-23 10:49 correction to check 1's wording: the decision MEETS PR #327's aim (one name for a coordinate, so map code reads one field without translating) the other way round. #327 adds physical_ to location to match statistical_unit; the owner's decision drops the prefixes so all say latitude, longitude, altitude, and with postal coordinates gone there is nothing left for physical_ to tell apart. The closing comment on #327 says so.

Correction 2026-11-26 (owner): Erik's comment on PR #327 (2026-11-14) asked only that rpc/statistical_unit_hierarchy and statistical_unit return the SAME names for latitude/longitude, for one generic map. His agent turned that into renaming location to physical_latitude, the opposite of the owner's choice. Owner: physical_ was there only because postal locations were systematically given a position too; StatBus records no position for a postal address (location rows carry coordinates only for type physical), so physical_ says nothing and goes. jbc5bs delivers Erik's wish: statistical_unit becomes latitude/longitude/altitude, matching location and the hierarchy RPC. PR #327 to be closed with a reply saying so, the reply approved by the owner first.

check 4: PR #327 closed 2026-11-26 with the owner-approved reply (tmp/pr327-reply.md): Erik's wish is met by jbc5bs, plain latitude/longitude/altitude everywhere.


check 2: Shipped with jbc5bs, commit 3bf2dbc6f on feat/coordinates-named-latitude: fast suite All 146 tests passed, doc/db and app types regenerated
check 3: Same commit: import definitions (source/data columns), samples/demo script, app/public/demo CSVs, test data, data-model.md, import-system.md, api-reference.md renamed; rg finds old names only in the refusal code and its tests
check 2: Shipped with jbc5bs on master b534af8e5; CI 46000665092 attempt 2 success
landed b534af8 on master 2026-11-27: db, app, test: coordinates are latitude, longitude, altitude; postal coordinates…
2026-11-27 13:45 (hibiscus) Closed with jbc5bs on master b534af8e5. Outcomes for the open-worded checks: check 1 = rename applied (plain names, not #327's direction); check 3 = rg finds old names only in migrations and in test 419 / the preview test, which show an old header meeting ordinary unknown-column handling (the refusal code was removed by the hard cut); check 4 = PR #327 closed 2026-11-26 with the owner-approved reply linking this task.
## History
- 2026-11-26T21:50 todo -> doing/active (take with jbc5bs)
- 2026-11-27T00:18 handed to rabbit: ox's session ended (closed 2026-11-26 23:16)
- 2026-11-27T01:12 doing/active -> doing/waiting (wait)
- 2026-11-27T11:06 request 1 by jhf
- 2026-11-27T11:06 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-27T13:41 resolved request 1 by hibiscus
- 2026-11-27T14:44 doing/waiting -> done (done); was doing_since: 2026-11-26T21:50; doing_with: jbc5bs; waiting_asked_by: rabbit; waiting_on: Hibiscus implements the rename with jbc5bs; waiting_since: 2026-11-27T01:12
