---
id: pkne34
title: "Missing region counts only domestic units with a physical location"
state: todo
type: bug
priority: "high"
assignee: []
labels: []
group: ""
rank: "zzzzzzx"
created: 2026-11-22
updated: 2026-11-22
---

## Goal
The Units Missing Region card and its list show domestic legal units and establishments that have a physical location but no region.

## Purpose
Owner 2026-11-22 on no.statbus.org: the list includes foreign units, which have no region by design. Units with no physical location already have their own card (89f3jm), so counting them here too reports one problem twice.

## Principle
Each data-quality problem shows on one card, and the card's exact count equals the total of the list it links to, for the selected time frame.

## Details
Today (app/src/app/dashboard/missing-region-card.tsx and the link in dashboard/page.tsx): physical_region_path IS NULL, unit_type not enterprise, existing at the frame's valid_on. No domestic filter and no physical-location filter. Note: statistical_unit.domestic is NULL for a unit without a physical location, which is likely why the Domestic Yes/No facets do not add up to the list total.

## Depends on

## Acceptance
- [ ] On a test database with a domestic unit without region, a foreign unit, and a unit without physical location, the card's exact count and its list both show only the domestic unit; a Playwright test asserts both numbers
- [ ] On no.statbus.org after the release, the card's exact count equals the list total; the numbers are recorded here

## Notes

2026-11-23 (Rabbit) Norway (rune) read-only, records valid today (tmp/slack-todos/validate.log): units with no region = 54,541 foreign (42,995 LU + 11,546 EST, domestic false) + 22,445 with no physical location (17,152 LU + 5,293 EST, domestic NULL) + 2 domestic with a location but no region (1 LU + 1 EST). So today's card counts about 77,000 where the owner's rule gives 2; domestic is NULL exactly for the units without a physical location (why Domestic Yes/No does not add up to the list).
