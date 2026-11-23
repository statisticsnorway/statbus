---
id: pkne34
title: "Missing Region counts domestic units that have a location but no region"
state: "doing"
type: bug
priority: "high"
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzx"
created: 2026-11-22
updated: 2026-11-22
doing_since: "2026-11-23T16:23"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
The Units Missing Region card and its list show domestic legal units and establishments that have a physical location but no region.

## Purpose
Owner 2026-11-22 on no.statbus.org: the list includes foreign units, which have no region by design. Units with no physical location already have their own card (89f3jm), so counting them here too reports one problem twice.

## Principle
Each data-quality problem shows on one card, and the card's exact count equals the total of the list it links to, for the selected time frame.

## Details
Before 7636c75cb (app/src/app/dashboard/missing-region-card.tsx and the link in dashboard/page.tsx) the card counted physical_region_path IS NULL, unit_type not enterprise, existing at the frame's valid_on, with no domestic or physical-location filter. Since then the card and its link share one definition (domestic, physical location present, region missing, not enterprise), and the search toolbar shows a Physical Location filter and any filter in effect even when its column is hidden. statistical_unit.domestic is NULL for a unit without a physical location, which is why the Domestic Yes/No facets do not add up to the list total.

## Depends on

## Acceptance
- [x] On a test database with one domestic unit that has a physical location but no region, one foreign unit, and one unit without a physical location, the card's exact count is 1 and its list has one row, that domestic unit; a Playwright test asserts both numbers
- [ ] On no.statbus.org after the release, the card's exact count equals the list total, and the list contains no foreign units and no units without a physical location; the numbers are recorded here

## Notes

2026-11-23 (Rabbit) Norway (rune) read-only, records valid today (tmp/slack-todos/validate.log): units with no region = 54,541 foreign (42,995 LU + 11,546 EST, domestic false) + 22,445 with no physical location (17,152 LU + 5,293 EST, domestic NULL) + 2 domestic with a location but no region (1 LU + 1 EST). So today's card counts about 77,000 where the owner's rule gives 2; domestic is NULL exactly for the units without a physical location (why Domestic Yes/No does not add up to the list).


check 1: 7636c75cb. Test slot fixture: domestic unit without region, a foreign unit, and a unit without physical location. tmp/pkne34/card-vs-list.mjs, card vs list total: RED 3 and 3 before (red.log), GREEN 1 and 1 after (green.log). The search toolbar now shows every filter a card applies. tmp/pkne34/filters-shown.mjs clicks each Data quality card: RED filters-red.log (Missing Region hid 'Physical Location Present', Missing Physical Location showed no chip), GREEN filters-green.log. filter-clear.mjs: clearing the chip drops the filter from the URL. tsc and eslint pass; owner saw it in Firefox.
Search toolbar: a filter whose column is hidden still shows while it narrows the search (FilterWrapper filterKeys), and there is a new Physical Location filter (present/missing). Check 2 waits for the next release on no.statbus.org.
landed 7636c75 on master 2026-11-23: app: Missing Region card counts what its list shows, and search names every…
62e05147c: the Establishment Activity Differs card lost quality= on a client-side visit (useSearchUrlSync had a second URL->state initializer without quality, which won the race when lookup data was cached). RED tmp/quality-click/repro.log (logo click and Back lose it), GREEN green.log. Physical Location Missing and Quality chips orange: tmp/quality-click/chip-colours.log.
Owner checked in Firefox on the test slot (62e05147c): the Establishment Activity Differs card opens the list with the Quality: Activity differs chip after a client-side return to the dashboard, and Physical Location: Missing and Quality chips show orange.
## History
- 2026-11-23T16:23 todo -> doing/active (take)
