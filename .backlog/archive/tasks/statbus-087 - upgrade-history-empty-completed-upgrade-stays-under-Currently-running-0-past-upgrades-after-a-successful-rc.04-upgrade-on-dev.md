---
id: STATBUS-087
title: >-
  upgrade-history-empty: completed upgrade stays under "Currently running" + "0
  past upgrades" after a successful rc.04 upgrade on dev
status: Done
assignee: []
created_date: '2026-06-18 12:47'
updated_date: '2026-06-18 14:59'
labels:
  - upgrade-ui
  - ux
  - post-rc.04
dependencies: []
priority: medium
ordinal: 87000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OBSERVED (King, dev.statbus.org, 2026-06-18, Software Upgrades page after upgrading to v2026.06.0-rc.04):
- The rc.04 upgrade (#254954, c4692562, Committed 18.6.2026, Scheduled 14:40:08, Completed 14:41:33) shows COMPLETED — but it is displayed under the "Currently running" section, not moved to history.
- "0 past upgrades" is shown despite the box clearly having upgraded (it is now on rc.04; it was on a prior version before).

QUESTIONS TO ANSWER (inspection delegated):
1. Why does a COMPLETED upgrade remain in "Currently running" instead of moving to the past/history list? (Frontend running-vs-past split logic.)
2. Why "0 past upgrades"? Are prior upgrades simply not recorded in public.upgrade (so genuinely zero history rows), or is the history query/filter wrong, or is the completed row being counted as "current" and excluded from "past"?
3. What is the correct UX: a completed upgrade should appear in history (and "Currently running" should be empty unless something is actually in progress).

EVIDENCE: screenshot in the 2026-06-18 session. Frontend page = the Software Upgrades view (app/); data = public.upgrade rows on dev. Post-rc.04 UX polish — NOT rc.04-blocking (the upgrade itself succeeded).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROOT CAUSE (mechanic, 2026-06-18) — frontend display logic, NO product/data bug.
(1) 'Currently running' header: the completed rc.04 row (#254954) is shown there because app/.../page.tsx:559 sets latestCompleted = history.find(state=='completed') — the 'what version am I on' anchor (intended).
(2) '0 past upgrades': page.tsx:730 counts filteredHistory.length, where filteredHistory hides state='superseded' by default (showSuperseded=false). Dev has 20 public.upgrade rows: #254954 completed (rc.04, the anchor) + 19 SUPERSEDED (edge-channel versions discovered but never applied — each superseded by the next master push before it ran). Non-superseded history = 0 → 'pebble 0 past upgrades'. The 19 superseded ARE present (the faded 'Superseded' chip reveals them); only the trigger count misleads.

FIX SHAPE: page.tsx:730 count historyRest.length (19) instead of filteredHistory.length, so the trigger reads '19 past upgrades' and signals there's history to expand.

UX CHOICE for the King: with the count = 19 but showSuperseded=false by default, expanding shows 0 rows until 'Superseded' is clicked. So the deeper choice is whether discovered-but-never-applied (superseded) rows should count/show as 'past upgrades' at all (rc.04 is the box's first APPLIED upgrade). Options: (a) count total 19 (mechanic's one-liner); (b) default showSuperseded=true so the history is visible; (c) relabel (e.g. 'N applied, M superseded'). King steers the exact UX. Post-rc.04, not blocking.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DONE — committed de453b814 + pushed. Root cause was display-only (the trigger counted non-superseded rows, so an all-superseded history read "0 past upgrades"). Fix (King's relabel choice): the Software Upgrades history trigger now shows "N applied · M superseded" (or just one when the other is 0). dev → "19 superseded", rune-after-rc.04 → "1 applied", mixed → "N applied · M superseded". tsc clean; foreman-reviewed (trivial frontend, no architect review needed). Reaches dev/no on their next upgrade.
<!-- SECTION:FINAL_SUMMARY:END -->
