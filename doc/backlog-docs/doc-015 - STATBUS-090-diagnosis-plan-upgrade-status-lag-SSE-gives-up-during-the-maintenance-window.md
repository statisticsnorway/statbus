---
id: doc-015
title: >-
  STATBUS-090 diagnosis + plan: upgrade-status lag (SSE gives up during the
  maintenance window)
type: specification
created_date: '2026-06-18 17:11'
tags:
  - upgrade-ui
  - maintenance
  - frontend
  - sse
  - architect-plan
  - root-cause
---
# STATBUS-090 — upgrade-status lag: root cause + plan

**Audience:** mechanic (frontend, primary), engineer (backend, minor), foreman (review). **Status:** root-caused (verified live code). **TL;DR:** the Software Upgrades page lags after an upgrade completes because the **SSE connection GIVES UP reconnecting during the minutes-long maintenance window** (`maxReconnectAttempts = 5`, ~31 s of backoff), so when the upgrade finishes the page's existing reconnect-refetch never fires and the completion NOTIFY is never received → stale until a manual refresh / tab-refocus. The robust fix is a **frontend polling fallback while an upgrade is active**; a small backend NOTIFY-ordering cleanup is secondary. (This supersedes my preliminary "backend NOTIFY-ordering is primary" — the operator's evidence + the live code show the SSE give-up is the root.)

## 1. Verified mechanism (live code, file:line)
**Frontend** (`app/src/atoms/JotaiAppProvider.tsx`, the live SSE manager):
- Subscribes to upgrade status via **SSE** `new EventSource('/api/sse/worker_status')` (:321). On `upgrade_changed` message → `refreshUpgradeStatus()` (:331-332). UI: `app/src/app/admin/upgrades/page.tsx` via `pendingUpgradeStatusAtom` (`atomWithRefresh`, upgrade-status.ts:23).
- **Reconnect-refetch EXISTS:** the `'connected'` handler calls `refreshInitialWorkerStatus()` (:354-356) → refreshes the upgrade status on every (re)connect. So "refetch on reconnect" is already implemented.
- **THE ROOT — the SSE gives up:** `onerror` (:359-374) closes + reconnects with backoff `min(1000·2^attempts, 30000)`, and **STOPS after `maxReconnectAttempts = 5`** (:313, :366-373 "Max reconnect attempts reached. Giving up."). `onopen` resets `reconnectAttempts` only on a SUCCESSFUL connect (:323-324). During maintenance, `/api/sse/worker_status` is 503'd by the Caddy `@maintenance` matcher (all paths except `/upgrade-progress.log`), so the EventSource never opens → 5 failed attempts exhaust in ~1+2+4+8+16 = **31 s** → the SSE GIVES UP. A real upgrade's maintenance window is **minutes** (binary swap, migrations, image pulls, archiveBackup), so the SSE reliably abandons reconnection well before the upgrade completes.
- **No polling fallback:** the upgrade-status atom is `atomWithRefresh` (manual refresh), refreshed only by SSE events + the `'connected'` reconnect + tab-focus reconnect. There is NO timer/poll. (The mechanic's triage note "falls back to SWR poll (3 s)" was wrong — that atom is not SWR.)

**Backend** (`cli/internal/upgrade/service.go applyPostSwap`, verified — line numbers had shifted from the triage):
- :4791 explicit `NOTIFY worker_status '{"type":"upgrade_changed"}'` fires while the row is STILL in_progress (comment :4787-4790 intended it as a "guarantee the app is listening" belt, but it's placed before the terminal write AND is emitted while maintenance is still on → no SSE listening → lost).
- :4808 `setMaintenance(false)`.
- :4833 `UPDATE state='completed'` → the DB trigger (migration 20260326174816) fires the REAL completion NOTIFY.
- The recovery path (:5055→:5059) already orders NOTIFY-after-completed correctly.

## 2. Root cause (one sentence)
The SSE abandons reconnection (give-up after 5 attempts ≈ 31 s) during the minutes-long maintenance window, so post-upgrade the existing reconnect-refetch never runs and the completion NOTIFY is never delivered → the page shows stale status until the operator manually refreshes or refocuses the tab. (Worst for the exact case the King hit: an operator WATCHING the upgrades page — no tab-refocus to rescue it.)

## 3. The fix
**PRIMARY — frontend polling fallback while an upgrade is active (mechanic, app/src):** while `pendingUpgradeStatusAtom` indicates a pending / in_progress upgrade (or a recently-active one), poll `/rest/upgrade` every N s (suggest 3–5 s) independent of the SSE, and stop when the row reaches a terminal state. This closes the gap REGARDLESS of SSE give-up/backoff — worst-case lag = N s. Fits the existing SWR "revalidate on interval" pattern (frontend.md). This is the robust, sufficient fix.

**SECONDARY — SSE resilience across the maintenance window (mechanic, same file):** don't permanently give up while an upgrade is active — e.g. keep retrying on a capped long interval (30 s) instead of stopping at 5 attempts, OR when `maxReconnectAttempts` is hit AND an upgrade is pending, schedule a slow re-init. Improves the realtime path so the poll rarely has to carry it. (The poll covers correctness; this restores live updates.)

**TERTIARY — backend NOTIFY cleanup (engineer, service.go; minor):** remove the premature :4791 in_progress NOTIFY (it's emitted while maintenance is on → never received, and would show in_progress if it ever were); rely on / move the completion NOTIFY to AFTER the :4833 terminal write (consistent with the recovery path :5059). Tidies the signal; does NOT fix the root (the SSE give-up does).

**REJECTED — reorder `state='completed'` BEFORE maintenance-off:** elegant (the row would be terminal before the user returns, so the reconnect-refetch sees completed), BUT it touches the delicately crash-safety-ordered completion sequence (§4a archiveBackup-reorder + rune-stuck fix-A: completed+removeFlag must precede archiveBackup; maintenance-off currently precedes completed so an interrupted maintenance-off still has the flag for recovery). Moving maintenance-off after completed risks a recovery-path crash-window regression, and the frontend poll closes the gap without that risk. Not worth it for a few-seconds UX bug. (If the King later wants 0-lag, it needs a dedicated crash-window analysis of the recovery path's handling of a completed-row-with-flag.)

## 4. Ownership / disjoint-ness
- **PRIMARY + SECONDARY = frontend (mechanic):** `app/src/atoms/JotaiAppProvider.tsx` (SSE) + `app/src/atoms/upgrade-status.ts` (the poll on `pendingUpgrade*`). 
- **TERTIARY = backend (engineer):** `service.go` NOTIFY cleanup.
- Frontend (app/src) ⊥ backend (service.go) → parallelizable. NOTE the primary is now FRONTEND (mechanic), not backend — corrects my preliminary framing.

## 5. STATBUS-088 overlap
088 (reword ~12 operator-facing jargon log lines) is a SEPARATE concern — no mechanism overlap with 090. 088's targets (service.go logRecover/progress.Write) are CO-LOCATED with 090's TERTIARY backend NOTIFY cleanup in service.go → if both are done, sequence them under the engineer (single service.go owner). 090's PRIMARY (frontend) is fully disjoint from 088.

## 6. Verification (the run is the oracle)
1. **Repro/observe:** on a real upgrade (or a long simulated maintenance), watch the upgrades page WITHOUT refocusing — confirm the SSE gives up (~31 s) and the page stays stale post-completion (the bug).
2. **Frontend unit/integration:** the poll starts when a pending/in_progress upgrade is observed, hits `/rest/upgrade`, and stops at terminal; the page reflects 'completed' within N s of the terminal write even with the SSE dead.
3. **End-to-end (STATBUS-071 arc or a rune-shaped box):** drive an upgrade, keep the page open, assert the page shows 'completed' within N s of the upgrade finishing (no manual refresh). This is the behaviour the King flagged.
