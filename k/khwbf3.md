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


2026-11-18 15:35 caught one (owner reload at 15:33:41.5 UTC, page hung, then appeared). Read from the stalled tab through the browser bridge right after, plus the owner's pasted console and the proxy log (tmp/stall/proxy-1533.log):
- Browser timeline (ms after navigation): HTML 153, DOM ready 260, first paint (the spinner) 281, all 27 scripts loaded by 360, load event 372. First app request (auth_status) started at 7,829; the REST data at 7,961.
- Proxy: no request from the browser between the scripts (15:33:43) and auth_status (15:33:50.92), apart from the dev server's HMR websocket and one /api/sse/worker_status that was aborted (incomplete response). Every request after that answered in 13-110 ms.
- Event journal and console: the first app log of this load is at 15:33:50.899 (NavigationManager CONTEXT_UPDATED, then RELOAD); auth checking -> idle_authenticated.stable at .925; navigation machine already idle (stable) throughout; isSetupLoading false at 51.019. So once the app's code ran, every machine settled within about 120 ms: in this stall no machine was stuck waiting; the app's code did not start for about 8 s after its scripts had loaded.
- Firefox does not report long tasks (longtask is not in PerformanceObserver.supportedEntryTypes), so the timeline cannot tell whether the main thread was busy or idle in those 8 s.
- The owner's console also shows, before the app's logs: 'Content script for gopassbridge initialized', 'The execution of microtasks on this page was reordered to avoid unsafe execution.' (a Firefox message), '[HMR] connected'. Recorded as observations, not as a cause.
Next observation that separates the possibilities: a Firefox Profiler recording across a reload that stalls (main thread activity in those 8 s), and console timestamps (Firefox console settings: Show Timestamps).
2026-11-18 15:50 Firefox Profiler recording of a 24 s stall (owner's reload 15:38:02; saved tmp/stall/profile-1538.json.gz; analysis scripts tmp/stall/profile_window.py, profile_markers.py; outputs tmp/stall/profile-1538-*.txt):
- The page's main thread (local.statbus.org content process, thread 53) was idle for the whole gap: 22,561 of 23,332 samples in __psynch_cvwait, about 5 ms of CPU per second. No JS ran, no long task, no GC of note. So the time was spent waiting on something, not computing.
- The page created its dev live-reload WebSocket (/_next/hmr) at 15:38:03.292, but Firefox only began connecting it at 15:38:26.289 (its DNS lookup starts then; the proxy's 101 log puts the request start at 15:38:26). The socket 'open' event fired at 15:38:26.315; the page then received messages at 26.319-26.38, and React logged 'Hydrated' at 26.382; the app's requests followed at 26.6.
- Next 16.4.5 turns on experimental.reactDebugChannel by default in dev (config-shared.js: reactDebugChannel: true; app-index.js passes debugChannel to createFromReadableStream for the initial page payload), and that channel's data arrives over the HMR WebSocket. Hydration came 67 ms after the socket opened, both times (15:33: HMR connected 50.848, first app log 50.896).
- During the 23 s that Firefox held the local socket back, another tab's HMR WebSocket was pending: https://test.statbus.org:3031/_next/hmr (the owner's tab at test.statbus.org:3031/login), STATUS_START 15:37:35.98 to 15:38:06.29 without a response. local.statbus.org and test.statbus.org both resolve to 127.0.0.1.
- Not yet shown: what held the local socket from 15:38:06 to 15:38:26, and whether Firefox's WebSocket admission rule (one connecting WebSocket at a time per remote host, RFC 6455 4.1) keys on the shared 127.0.0.1. Next step: reproduce in driven Firefox with a second page holding a connecting WebSocket to 127.0.0.1 on another port, and measure the local page's time to hydrate with and without it.
## History
- 2026-11-18T16:33 todo -> doing/active (take)
- 2026-11-18T16:33 doing/active -> doing/waiting (wait)
