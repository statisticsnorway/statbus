---
id: STATBUS-090
title: >-
  upgrade-status-lag: Software Upgrades page lags behind after the upgrade
  completes (refresh on return from maintenance, or service delay?)
status: To Do
assignee: []
created_date: '2026-06-18 13:00'
updated_date: '2026-06-18 13:07'
labels:
  - upgrade-ui
  - maintenance
  - post-rc.04
dependencies: []
priority: medium
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OBSERVED (King, no.statbus.org rc.04 upgrade, 2026-06-18): after the upgrade completed, the Software Upgrades page (and/or the app's sense of "what version am I on") lagged behind — it didn't promptly reflect the completed upgrade / new version after the redirect back from maintenance.

QUESTION TO ANSWER (King's framing): is the lag (a) the UI not refreshing after the redirect back from the maintenance page — stale client state, no re-fetch on return — or (b) the upgrade SERVICE delaying the row/version update (completion not propagating promptly)?

INSPECTION (delegated):
- The post-upgrade return flow: when the site comes back from maintenance, does the app force a fresh load / re-fetch the upgrade status + version, or does it show cached/stale state until a manual refresh?
- The upgrade-status data freshness: does the service mark the row completed + the running version promptly, and does the page poll/subscribe for it (the "Checking..." / auto-update mechanism seen on the page)?
- Determine which of (a)/(b) it is; cite the relevant frontend + service code.

Related to STATBUS-089 (same maintenance-during-upgrade lifecycle, the return half). Post-rc.04 UX; not blocking.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROOT CAUSE (mechanic, 2026-06-18) = (b) service-timing + LISTEN-reconnect race, NOT a stale-UI/no-refetch issue.
Completion sequence in applyPostSwap: (1) service.go:4456 NOTIFY worker_status 'upgrade_changed' fires while the row is STILL in_progress; (2) :4473 setMaintenance(false); (3) ~:4481 UPDATE state='completed' → DB trigger pg_notify('worker_status','upgrade_changed') (migration 20260326174816); (4) removeUpgradeFlag.
Step 1's NOTIFY reaches the frontend while still in_progress → UI re-fetches, sees no change. The REAL completion signal is step 3's trigger-NOTIFY. But the app's LISTEN/SSE may not be re-established yet (it was just coming back from the maintenance window), so the completed event is MISSED → frontend falls back to the SWR poll (3s cadence) → worst-case lag ~3s + a missed-event round-trip. The code already warns of this at service.go:4453-4455.
FIX SHAPE (post-rc.04): fire the operator-facing completion NOTIFY AFTER the state='completed' UPDATE (not before), and/or have the frontend force a re-fetch on SSE reconnect, and/or tighten the poll while an upgrade is active. Not data-loss; a few-seconds UX lag.
<!-- SECTION:NOTES:END -->
