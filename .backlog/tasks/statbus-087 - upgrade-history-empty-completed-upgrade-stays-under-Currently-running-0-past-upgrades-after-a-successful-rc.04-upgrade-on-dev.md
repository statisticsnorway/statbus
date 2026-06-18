---
id: STATBUS-087
title: >-
  upgrade-history-empty: completed upgrade stays under "Currently running" + "0
  past upgrades" after a successful rc.04 upgrade on dev
status: To Do
assignee: []
created_date: '2026-06-18 12:47'
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
