---
id: rwavxg
title: "Quality card colours follow the number shown, and a pending count says so"
state: "done"
type: bug
priority: "low"
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzy"
created: 2026-11-22
updated: 2026-11-22
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
done_at: "2026-11-23T21:54"
---

## Goal
A quality card's colour comes from the number it shows (saved or estimated) at once, and a count still being fetched is marked with ~.

## Purpose
Owner 2026-11-22: quality card colours lag behind their numbers, which appear early.

## Principle
The card's colour and number come from the same value at the same moment.

## Details
Cards set failed from the estimated count state (e.g. missing-region-card.tsx failed={!!error || (count ?? 0) > 0}) while EstimatedCount shows a saved exact count from localStorage immediately, so colour waits for the estimate fetch. Related: the dashboard count ticket.

## Depends on

## Acceptance
- [x] With a saved count of 0 and of 5, a card shows the right colour on first paint; a Playwright test asserts the colour before the estimate request answers
- [x] While the exact count is being fetched the number shows ~; a test asserts it

## Notes


check 1: adb5b7d2e. tmp/rwavxg/colour-follows-number.mjs holds the estimate and exact requests unanswered and reads the Missing Region card. RED (red.log): saved 5 showed '-' and grey; saved 0 with estimate 3 showed ~3 orange. GREEN (green.log, three runs): saved 5 shows 5 orange, saved 0 shows 0 grey, before any estimate answers.
check 2: Same test: with no saved count and the exact request unanswered, the card shows ~3 (orange) and ~0 (grey); EstimatedCount already prefixes estimates with ~, and the test asserts the text.
landed adb5b7d on master 2026-11-23: app: quality card colour follows the number it shows (rwavxg)
Pending marker as built: a card shows its estimate as ~N (e.g. ~3) until the exact count arrives, then N. Related dashboard count ticket: dwt9kd.
## History
- 2026-11-23T21:41 todo -> doing/active (take with pkne34)
- 2026-11-23T21:54 doing/active -> done (done); was doing_since: 2026-11-23T21:41; doing_with: pkne34
