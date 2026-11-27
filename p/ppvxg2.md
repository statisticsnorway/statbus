---
id: ppvxg2
title: "Search map circles can be sized by a statistical variable"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-27
updated: 2026-11-27
---

## Goal
On the search map a region's circle can be sized by a statistical variable, such as employees, not only by its count of units.

## Purpose
Counting units shows where businesses are registered; sizing by employees or turnover shows where activity is. Raised with the owner during the 5nq78t map work.

## Principle
Sums come from the same filter and existence rule as the list; a variable that does not add up across units is not offered.

## Details
Today circles are sized by unit count per region (5nq78t, regions-map.tsx). statistical_unit_facet carries stats_summary per facet; the live path aggregates statistical_unit. Owner has not yet decided whether this is wanted.

## Depends on

## Acceptance
- [ ] [Owner] Decides whether circles can be sized by a variable, and which variables; recorded here
- [ ] With a variable chosen, each circle's size follows the variable's sum for the region, equal to a SQL sum with the same filter (jest on the helper, SQL comparison recorded)

## Notes
