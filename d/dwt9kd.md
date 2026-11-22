---
id: dwt9kd
title: "Every dashboard card's count equals its list, for the selected time frame"
state: todo
type: bug
priority: "high"
assignee: []
labels: []
group: ""
rank: "zzzzzzz"
created: 2026-11-22
updated: 2026-11-22
---

## Goal
Each dashboard card's exact count equals the total of its linked list for the selected frame, after any frame or data change.

## Purpose
Owner 2026-11-22: no.statbus.org Missing Region card about 100 000, its list about 76 000; other dashboard vs list mismatches; numbers right only after live, previous, cache clear, live; on dev the 2024 cards do not match the reports.

## Principle
A card and its list ask the same question; a saved count belongs to one frame and one state of the data and is never shown for another.

## Details
Found 2026-11-22 (app/src/components/estimated-count.tsx): (1) exactCount state is seeded from localStorage once; on a cacheKey (frame) change the cacheInvalidation effect only clears it when the new key has no saved count, so a frame whose count is saved keeps showing the previous frame's number. (2) localStorage exact counts never expire; they are cleared only when this open browser sees is_importing or is_deriving_statistical_units finish, so changes seen from another browser or while closed leave stale numbers. Card queries and the search list use the same existence rule (lib/unit-existence.ts) on valid_on. Domestic Yes/No cannot sum to the list while domestic is NULL for units without a physical location (see pkne34). Dev 2024 vs reports not yet inspected: either this cache fault or a different count in reports. Colours: rwavxg.

## Depends on

## Acceptance
- [ ] Switching the time frame shows each card's count for that frame; a Playwright test switches between two frames with different counts and asserts both
- [ ] A saved count is tied to the data's last change and is not shown after it; a test changes data from another session and asserts the card refetches
- [ ] For every card that links to a list, a Playwright test asserts the card's exact count equals the list total for two frames
- [ ] On dev, the 2024 cards match the reports and their lists; the cause of the earlier mismatch and the numbers are recorded here

## Notes
