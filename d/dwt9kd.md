---
id: dwt9kd
title: "Every dashboard card's count equals its list, for the selected time frame"
state: "doing"
type: bug
priority: "high"
assignee: ["rabbit"]
labels: []
group: ""
rank: "00000000000f"
created: 2026-11-22
updated: 2026-11-22
doing_since: "2026-11-23T22:27"
doing_with: "pkne34"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
Each dashboard card's exact count equals the total of its linked list for the selected frame, after any frame or data change.

## Purpose
A user reads the dashboard to know the register's state for a chosen time; a card that shows another frame's number, or disagrees with its own list, makes every figure doubtful.

## Principle
A card and its list ask the same question; a saved count belongs to one frame and one state of the data and is never shown for another.

## Details
Observed (owner 2026-11-22): no.statbus.org Missing Region card about 100 000, its list about 76 000; other dashboard vs list mismatches; numbers right only after live, previous, cache clear, live; on dev the 2024 cards do not match the reports.

## Depends on

## Acceptance
- [x] Switching the time frame through the Time frame menu shows each card's count for that frame: with both frames' exact counts saved, switching 2024 -> live -> 2024 shows the Legal Units card 6, 31, 6 (the exact counts) on the test slot; a Playwright test asserts each
- [x] A saved count is tied to the data's last change and is not shown after it; a test changes the data from another session and asserts the card then shows the new exact count
- [x] For every card that links to a list, a Playwright test asserts the card's exact count equals the list total for two frames
- [ ] On dev, the 2024 cards match the reports and their lists; the cause of the earlier mismatch and the numbers are recorded here

## Notes

2026-11-23 (Rabbit) Reproduced in a real browser on the test slot (tmp/dwt9kd/repro2.mjs, log repro2.log, journal 11:26): exact legal unit counts live 31, 2024 6; after both are saved, switching in-page from 2024 to live leaves the Legal Units card at 6. The script is the RED case for the first check.


check 1: adb5b7d2e (saved counts read per cacheKey via useSavedExactCount). tmp/dwt9kd/frame-switch.mjs switches 2024 -> live -> 2024 through the Time frame menu, with both frames' exact counts saved. RED on adb5b7d2e~1 (frame-switch-red.log): back on 2024 the Legal Units card showed 31, live's number. GREEN on HEAD (frame-switch.log): 6, 31, 6 = exact counts.
Data change not reflected (check 2), RED: tmp/dwt9kd/data-change.mjs, data-change.log (card 0, exact 1 after 60 s). The SSE stream delivers is_deriving_* stop events (sse-watch.log, trace2.log), yet no saved count is removed: worker_status.ts clears saved counts only on a true->false edge of isDerivingUnits, which fast derivations do not produce reliably. Frame switching (check 1) holds since adb5b7d2e. Dev data, live frame: Legal Units card 7593 vs list 7961, Establishments 1562 vs 1672; the gap is the units whose status is not used_for_counting (dev statuses 1, 3, 4); quality cards match their lists.
landed 2dd8393 on master 2026-11-23: app: unit count cards link to the units they count (dwt9kd)
check 3: 2dd83934d. tmp/dwt9kd/cards-vs-lists.mjs picks each frame in the Time frame menu, waits for each card's exact count, clicks it and reads the list total. Dev data (live): Legal Units 7593 vs list 7961, Establishments 1562 vs 1672, Enterprises 7593 vs 7961 (the units whose status is not used_for_counting); quality cards matched (cards-vs-lists-devdata.log). Test slot with legal unit 25 passive (tmp/dwt9kd/passive-fixture.sql, restored): RED before the fix 55/56 and 30/31 (unit-links-red.log); GREEN after, all 7 cards equal their lists for Live frame (2026) (unit-links-green.log) and Frame 2024 (unit-links-green-2024.log).
Check 2 cause: db-listener relayLatest coalesces worker_status per type in 500 ms windows; a ~0.5 s derivation reaches the browser as a stop alone (tmp/dwt9kd/diag.log), so the true->false edge in worker_status.ts never cleared saved counts. Fix d5d29f4c4: saved counts stamped {v: data version, n} where version = latest completed derive_units/reports_phase (via /rest/worker_task, 'none' when purged); shown only while current; version read on load and on every stop event; cards add dataVersion to their estimate fetch deps. Known limit: purge-to-'none' after 7 idle days re-saves counts once (harmless).
check 2: tmp/dwt9kd/data-change.log RED (0 vs exact 1) -> data-change-green.log PASS (card 0 -> 1 in 12 s, live SSE); reload variant tmp/dwt9kd/data-change-reload.mjs -> data-change-reload-green.log PASS (stale stamped 0 in storage, page reload shows - , ~5, 1; never 0). frame-switch, colour-follows-number (updated to stamped format), filters-shown PASS; jest 127/127, tsc, eslint clean. Data restored (82,84,85: country 237, region 43). Commit d5d29f4c4.
## History
- 2026-11-23T22:27 todo -> doing/active (take with pkne34)
