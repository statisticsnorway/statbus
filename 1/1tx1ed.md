---
id: 1tx1ed
title: "Quality checks start switched off; the owner picks a sensible starting set"
state: "doing"
type: feature
priority: ""
assignee: ["opus-a"]
labels: []
group: ""
rank: "zzzzzzzzzzzw"
created: 2026-11-26
updated: 2026-11-26
doing_since: "2026-11-26T21:22"
doing_with: "qjy2eg"
stage: "active"
model: "claude-opus-5-5"
branch: "quality/default-off-secondary-equals-primary"
worktree: "/Users/jhf/ssb/statbus_a"
---

## Goal
A new installation shows only an agreed starting set of quality checks; every other check starts switched off and an admin switches it on.

## Purpose
Owner 2026-11-26: the number of quality checks on the dashboard is overwhelming; start with them disabled and let users enable the ones they want.

## Principle
The catalogue stays one view; the switch table today records checks switched off (absence = on). Default off means inverting it to record checks switched on, with a forward migration that keeps every installation's current visible set. Decide the starting set with the owner before building.

## Details
Today: public.quality_check_switched_off (05pe0x), reset's customisation scope empties it. Inverted: quality_check_switched_on, seeded with the starting set; reset restores the starting set. Dashboard text 'N switched off · Edit' becomes 'N more checks · Edit' or similar. Candidate starting set to discuss: missing region, missing activity category, missing physical location.

## Depends on

## Acceptance
- [x] [Owner] approves the starting set, recorded on this task
- [ ] On a fresh install the dashboard shows exactly the starting set; Admin > Data quality checks lists the rest switched off
- [x] An upgraded installation keeps the checks it showed before the upgrade

## Notes

check 1: Owner agreed 2026-11-26 12:16: starting set on = missing region, missing activity category, secondary equals primary (qjy2eg); off = missing physical location, establishment has another activity, and the two per-variable LU/ES checks.

Owner 2026-11-26 20:10: the starting set on = missing region, missing activity category, secondary activity equals primary (qjy2eg, on by default). All others start off.


check 3: test/sql/414 replays the shipped down/up of 20261126202817 with 3 checks switched off: visible_before 8 = visible_after 8, same_checks_visible t; RED (relation switched_on missing) and GREEN logs in tmp/. Norway copy on slot a kept all 7 checks on after migrating.
Fresh DB: seed after recreate shows exactly missing_region, missing_activity_category, secondary_activity_equals_primary (test 411.2); reset customisation restores them (411.11). Check 2 needs a browser look on a fresh install (not done here).
## History
- 2026-11-26T21:22 todo -> doing/active (take with qjy2eg)
