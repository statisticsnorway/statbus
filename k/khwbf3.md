---
id: khwbf3
title: "The app sometimes stays on Loading application… after a reload"
state: "doing"
type: bug
priority: "high"
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzzq"
created: 2026-11-18
updated: 2026-11-18
doing_since: "2026-11-18T16:33"
stage: "waiting"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
waiting_on: "the next stalled load: the owner says 'slow' while still on the page, and hibiscus reads its timeline and state through the browser bridge"
waiting_since: "2026-11-18T16:33"
waiting_asked_by: "hibiscus"
---

## Goal
Every load of the app shows the page as soon as its data is ready; it never stays on 'Loading application…' until the user reloads.

## Purpose
For about a month the owner has met loads that hang on 'Loading application…' and get out only by reloading, and he keeps a rescue that reloads when nothing happens. It is a daily annoyance and hides real failures. Many diagnostics were built (Debug Inspector journals, client and server logging) without catching the cause.

## Principle
Observe before explaining: no fix from a hunch. The cause is caught in a stalled load's own evidence (browser timeline, state, journal, server log), reproduced in a test, then fixed declaratively in the state machines, not by another rescue. Owner's theory (2026-11-18): a timing race that the XState machinery does not capture.

## Relevant details
Investigation 2026-11-18 (hibiscus with the owner, local slot https://local.statbus.org:3011, dev server :3017, Norway data).

What gates the page (app/src/atoms/JotaiAppProvider.tsx, PageContentGuardInner): it shows the fallback while the navigation machine (app/src/atoms/navigation-machine.ts) is not in a state tagged 'stable' (idle is) or while isLoadingAuth, which is !initialAuthCheckCompletedAtom (app/src/atoms/app-derived.ts appReadyAtom), set by the effect AppInitializer:setInitialAuthCheckCompleted. PageContentGuard also shows it until the client has mounted. The Debug Inspector is rendered outside the guard (app/src/app/layout.tsx), so it works during a stall.

Observed: one slow load at 15:28:51 (after the inspector's Clear Caches, which clears localStorage hasStatisticalUnits and the exact-count cache). Proxy log (tmp/stall/proxy-1529.log): GET / 112 ms and all script chunks 304 in 15-35 ms at 15:28:51, then no request at all for 5 s, then at 15:28:56 the app starts (auth_status first) and every request answers in 3-30 ms. So the time went inside the browser, before the app's first request, not to the server or network. A second Clear Caches reload was fast; the stall did not come back while watched.

Fast-load baseline in the owner's Firefox (15:29:27, read through the browser bridge): HTML 450 ms, DOM ready 564, last script 698, load event 707, first app request (auth_status) 746 ms.

Not reproduced: 30 fresh tabs and 30 reloads of one tab in a Playwright-driven Firefox, and 20 in Chromium, all 0.5-3 s (one connection refused is a different failure); the owner's own reloads and token expiry/refresh through the Debug Inspector, all fast. Machine load 60-190 at the time: not the cause (the owner: everything else loads normally). Mount journal during fast loads: 2 per effect (React Strict Mode), 14 for EstimatedCount (7 dashboard cards): no loop.

Tools: the jcode browser bridge runs JavaScript in the owner's Firefox tab (page world: window.__STATBUS_CONFIG__, performance entries) but does not capture console or network; a driven Firefox or Chromium (Playwright, scripts tmp/hug/stall-loop*.mjs, stall-reload.mjs) captures console, every request and pending ones. Proxy log: docker compose logs --no-log-prefix proxy, decoded with jq (tmp/stall/).

## Depends on

## Acceptance
- [ ] A stalled load is caught with its own evidence: the browser timeline (navigation and resource timing, long tasks) read from the stalled tab, the Debug Inspector state and event journal, and the proxy log of the same minute; recorded in the notes
- [ ] The cause is named from that evidence and reproduced by a test that fails with it
- [ ] The fix is in the state machines or derived state (no new rescue), the test passes, and the owner sees no stall over a working day; the owner's reload rescue is then removed

## Notes


## History
- 2026-11-18T16:33 todo -> doing/active (take)
- 2026-11-18T16:33 doing/active -> doing/waiting (wait)
