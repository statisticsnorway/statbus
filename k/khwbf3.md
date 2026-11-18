---
id: khwbf3
title: "The app sometimes stays on Loading application… and only a reload clears it"
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
Observe before explaining: no fix from a hunch. The cause is caught in a stalled load's own evidence (browser timeline, profile, state, journal, server log), reproduced in a test, then fixed where the evidence puts it, not by another rescue. Owner's theory (2026-11-18): a timing race that the XState machinery does not capture.

## Relevant details
What gates the page (app/src/atoms/JotaiAppProvider.tsx, PageContentGuardInner): it shows the fallback until the client has mounted, while the navigation machine (app/src/atoms/navigation-machine.ts) is not in a state tagged 'stable', or while isLoadingAuth (!initialAuthCheckCompletedAtom, app/src/atoms/app-derived.ts). The Debug Inspector is rendered outside the guard (app/src/app/layout.tsx), so it works during a stall.

Stall evidence (2026-11-18, local slot https://local.statbus.org:3011, dev server :3017, Next 16.4.5 with Turbopack, owner's Firefox 160 on macOS):
- 15:33:41 reload, 8 s, and 15:38:02 reload, 24 s (Firefox Profiler recording, tmp/stall/profile-1538.json.gz). Both times the HTML and every script arrived within 0.4 s and the spinner was painted, and then the page's main thread sat idle (no JS, no long task) until its dev live-reload WebSocket (/_next/hmr) opened; React hydrated about 70 ms after that and every machine settled within about 120 ms.
- Firefox created that WebSocket at once (15:38:03.29) but started connecting it only at 15:38:26.29. Meanwhile another tab's WebSocket to https://test.statbus.org:3031/_next/hmr was pending without a response (15:37:35.98-15:38:06.29). Both host names resolve to 127.0.0.1.
- Next 16.4.5 enables experimental.reactDebugChannel by default in development (node_modules/next/dist/server/config-shared.js); app-index.js passes that channel to the decode of the initial page payload, and its data comes over the HMR WebSocket.

Tools: the jcode browser bridge runs JavaScript in the owner's Firefox tab (page world, performance entries, sessionStorage eventJournal); the Firefox Profiler (Ctrl+Shift+1) records a reload, saved via Save and analysed with tmp/stall/profile_window.py and profile_markers.py; Playwright Firefox/Chromium (tmp/hug/stall-loop*.mjs, stall-reload.mjs) captures console and requests; the proxy log comes from docker compose logs --no-log-prefix proxy with jq (tmp/stall/).

## Depends on

## Acceptance
- [x] A stalled load is caught with its own evidence: the browser timeline (navigation and resource timing, long tasks) read from the stalled tab, the Debug Inspector state and event journal, and the proxy log of the same minute; recorded in the notes
- [x] The cause is named from that evidence and fixed at that cause (no new rescue); a driven-Firefox test shows the stall with the cause present before the fix, and the page hydrating within 2 s after it
- [ ] [Owner] works a full day on the local slot in Firefox and says in this task's notes whether a load stalled; a stall is captured with a profile as new evidence and reopens the cause, a clean day lets the reload rescue in JotaiAppProvider.tsx be removed

## Notes
- Earlier attempts (2026-11-18 morning), kept for the record: one slow load at 15:28:51 after the inspector's Clear Caches (proxy log tmp/stall/proxy-1529.log: 5 s with no request after the scripts). Not reproduced in 30 fresh tabs and 30 reloads in Playwright Firefox, 20 in Chromium (0.5-3 s each), or by the owner's reloads and token expiry tests. Machine load 60-190 then, not the cause. Mount journal during fast loads: 2 per effect (Strict Mode), 14 for EstimatedCount: no loop. Fast-load baseline in the owner's Firefox: first auth_status at 746 ms.



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
check 1: Two stalls caught 2026-11-18: 15:33:41 (8 s; bridge timing, event journal, console, proxy log tmp/stall/proxy-1533.log) and 15:38:02 (24 s; Firefox Profiler tmp/stall/profile-1538.json.gz, proxy log tmp/stall/proxy-1538.log). Main thread idle until the /_next/hmr WebSocket opened; hydration 67-70 ms later.
check 2: Cause: Next 16.4.5 dev enables experimental.reactDebugChannel, so hydration waits for the /_next/hmr WebSocket; Firefox connects one WebSocket per IP at a time and every local slot is 127.0.0.1, so a stuck socket in another tab (the owner's test.statbus.org:3031 tab in the 15:38 profile) held the page. Fix e421c0c1f sets reactDebugChannel: false in app/next.config.js (dev only). Driven-Firefox test tmp/stall/ws-block-repro.mjs with a page holding stuck wss://test.statbus.org:39999 sockets: before the fix 19.7 s then not shown within 40 s on 3 of 4 reloads (tmp/stall/repro-test.log); after it 1.7-2.3 s (tmp/stall/repro-test-fixed.log), baseline 0.8-1.6 s. Hot reload still updates in place (tmp/stall/hmr-check.mjs: 0 full reloads). WebSockets over HTTP/2 do not avoid the queue: a throwaway Caddy with GODEBUG=http2xconnect=1 served the socket as HTTP/2 CONNECT, and with the stuck socket present it still opened only after 18.5 s (tmp/stall/h2ws/).
2026-11-18 16:16 a first try of the same setting coincided with the owner's tab reloading / every 0.7 s for about 2 minutes (proxy log); reverted, the loop stopped. Re-applied at 16:25 and 16:28: one reload on the dev server's restart, no loop (observed 45 s and 30 s in the proxy log, and a driven page's HMR frames in tmp/stall/reload-loop-observe.log). The loop was not reproduced; the first restart also logged a ChunkLoadError for the hmr-client chunk in the owner's tab. If a loop recurs, capture it with a profile.
landed e421c0c on master 2026-11-18: app: dev pages hydrate without waiting for the HMR WebSocket (khwbf3)
## History
- 2026-11-18T16:33 todo -> doing/active (take)
- 2026-11-18T16:33 doing/active -> doing/waiting (wait)
