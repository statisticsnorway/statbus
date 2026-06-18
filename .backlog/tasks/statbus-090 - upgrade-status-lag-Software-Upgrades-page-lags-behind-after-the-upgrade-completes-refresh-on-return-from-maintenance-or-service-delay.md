---
id: STATBUS-090
title: >-
  upgrade-status-lag: Software Upgrades page lags behind after the upgrade
  completes (refresh on return from maintenance, or service delay?)
status: To Do
assignee: []
created_date: '2026-06-18 13:00'
updated_date: '2026-06-18 17:11'
labels:
  - upgrade-ui
  - maintenance
  - post-rc.04
dependencies: []
documentation:
  - doc-015
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

ARCHITECT DIAGNOSIS + PLAN (2026-06-18) = backlog doc-015. ROOT CAUSE (verified live code, refined from the mechanic's triage): the SSE connection GIVES UP reconnecting during the minutes-long maintenance window. app/src/atoms/JotaiAppProvider.tsx: EventSource('/api/sse/worker_status') (:321); onerror backoff min(1000*2^attempts,30000) STOPS after maxReconnectAttempts=5 (:313,:366-373) — ~31s total; onopen resets attempts only on a SUCCESSFUL connect (:323-324). Maintenance 503s the SSE endpoint, so it never opens → 5 attempts exhaust in ~31s → GIVES UP. A real upgrade's maintenance is MINUTES → the SSE abandons reconnection before completion → post-upgrade the EXISTING reconnect-refetch ('connected' → refreshInitialWorkerStatus, :354-356) never fires + the completion NOTIFY is never received → page stale until manual refresh/tab-refocus. Worst for an operator WATCHING the page (the King's case). NO polling fallback exists (the upgrade-status atom is atomWithRefresh, not SWR; the triage's '3s SWR poll' was wrong).

FIX: PRIMARY (frontend/mechanic) = polling fallback while a pending/in_progress upgrade exists — poll /rest/upgrade every 3-5s independent of the SSE, stop at terminal (closes the gap regardless of SSE give-up; worst-case lag = N s). SECONDARY (frontend) = SSE resilience across maintenance (don't permanently give up while an upgrade is active). TERTIARY (backend/engineer, minor) = remove the premature in_progress NOTIFY (service.go:4791) + emit completion NOTIFY after the :4833 terminal write (consistent w/ recovery :5059) — does NOT fix the root. REJECTED: reorder state='completed' before maintenance-off — touches the §4a/rune-stuck crash-safety completion sequence; the poll closes it without that risk. OWNERSHIP: primary = FRONTEND (mechanic, app/src) — NOT backend as my preliminary framed; backend tertiary = engineer, foldable with 088. 088 is co-located in service.go w/ the tertiary cleanup (sequence under engineer) but otherwise disjoint. Full plan + verification: doc-015.
<!-- SECTION:NOTES:END -->
