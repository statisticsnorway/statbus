---
id: f2gx3m
title: "Totals that do not add up on jo: a unit counted before its birth date"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "00000000000f"
created: 2026-11-26
updated: 2026-11-26
---

## Goal
A legal unit's total counts only units that exist in the period, and imports refuse a birth date in a year after valid_from.

## Purpose
jo.statbus.org, Frame 2023, Drill Down Norway AS (establishment 89): the legal unit shows Employees 23 own and Σ 25, Turnover 20 023 own and Σ 20 066, but its one visible establishment holds Employees 0 and Turnover 23, so the sums do not reconcile. The owner's hypothesis: a unit counts as valid before it is born.

## Principle
Reproduce first: a test with jo's shape fails before the fix and passes after. Count a unit only where it exists. Validate at import, never repair silently: a birth_date in a later calendar year than the row's valid_from is an error on that row; a birth_date later in the same year stays valid. Do not start before the owner plays it back; this ticket is not yet due.

## Details
Owner request 1 (2026-11-26 21:15). Image paste-1540.png (jo.statbus.org/establishments/89/links?details=true, Frame 2023): 23 + 0 vs Σ 25 employees, 20 023 + 23 vs Σ 20 066 turnover. The team asked: birth_date after valid_from is invalid; the owner refines it to a later year than valid_from. Find which units feed 25 and 20 066 (an establishment not shown under Frame 2023, or one valid before its birth_date) on a copy of jo's data.

## Depends on

## Acceptance
- [ ] Verify Counting issue in jo.statbus.org
- [ ] [Owner] plays the ticket back and approves the plan before work starts; answer recorded in Notes
- [ ] A SQL test reproduces jo's case for both Employees and Turnover: it fails on master and passes after the fix
- [ ] An import row whose birth_date is in a later year than its valid_from is refused with an error naming both dates; a birth_date later in the same year is accepted
- [ ] On a copy of jo's data, Drill Down Norway AS's legal unit total equals its own value plus its existing establishments' values for Frame 2023

## Requests
- 2026-11-26T21:15 request 1 by jhf:
  The issue here is twofold. One, if you look at the count in the image, you will see that they don't add up. And the question is why. And I think it is because something is valid that isn't born, and then thus the counting has to have a mistake. We have to fix the test, have it fail, and then the counting will be correct. However, I think we can catch it with a validation. The team asked for birth date has to be after valid has to be before valid from. That is invalid. But I think birth date can't be more than a year in the future from valid from. Meaning if you are valid from a year, then you have to be born in the same year, not a later year, and we shall do it during validation. All of this must be played by me when this ticket is due. It is not yet.
  resolved 2026-11-26T21:15 by rabbit:
    Ticket rewritten from the request: title, goal, purpose (the jo numbers that do not add up: 23+0 vs Σ 25, 20 023+23 vs Σ 20 066), principle (reproduce with a failing test first; count a unit only where it exists; at import refuse a birth_date in a later year than valid_from, allow later in the same year; wait for the owner's play-back), details, and four acceptance checks starting with the owner's approval. Not started: the ticket is not yet due.

## Notes

file:paste-1540.png (169473 bytes, sha256:f4f591fe) pasted from the clipboard in hug tui


## History
- 2026-11-26T21:15 request 1 by jhf
- 2026-11-26T21:15 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T21:15 request 1 acknowledged by rabbit
- 2026-11-26T21:15 request 1 in progress by rabbit: hug task set f2gx3m
- 2026-11-26T21:15 resolved request 1 by rabbit
