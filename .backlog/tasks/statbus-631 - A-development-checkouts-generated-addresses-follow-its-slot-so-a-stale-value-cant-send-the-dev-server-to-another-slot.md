---
id: STATBUS-631
title: >-
  A development checkout's generated addresses follow its slot, so a stale value
  can't send the dev server to another slot
status: To Do
assignee: []
created_date: '2026-11-16T13:10:00Z'
updated_date: '2026-11-16T13:46:00Z'
labels:
  - dev-tooling
dependencies: []
priority: high
type: bug
ordinal: 542204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In development, sb config generate derives STATBUS_URL, BROWSER_REST_URL and SERVER_REST_URL from SITE_DOMAIN and the slot's ports, but writes them to .env.config once and then keeps whatever is there (gen() fills only missing keys). The test checkout still held SERVER_REST_URL=http://proxy:80 and STATBUS_URL=http://localhost:3013 from an earlier setup: the host dev server's auth check failed with ENOTFOUND proxy on every request, and the page reloaded to /login in a loop (owner 2026-11-16 13:06). BROWSER_REST_URL pointed at another slot's REST (localhost:3013). Each new checkout or reboot repeats the diagnosis. Design to decide: in development mode, sb config generate either derives these three from SITE_DOMAIN and the slot (unless the operator declares an override explicitly), or refuses with the expected value when a declared value names another slot's port or a docker-only host; pnpm run dev runs the same check before starting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 In development, after sb config generate, SERVER_REST_URL, STATBUS_URL and BROWSER_REST_URL in .env name this checkout's SITE_DOMAIN and slot ports (Go test with a .env.config holding http://proxy:80 and another slot's port)
- [ ] #2 pnpm run dev refuses to start, naming the key and the expected value, when .env still holds an address the dev server can't reach
- [ ] #3 In the test checkout, a fresh pnpm run dev after ./dev.sh https on signs in at https://local.statbus.org:3031 without hand edits
- [ ] #4 Two slots on the same host (local.statbus.org:3011 and :3031) stay signed in side by side: signing in on one leaves the other signed in (observed in Firefox)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-16 13:45, the second half of this ticket: since both checkouts use SITE_DOMAIN=local.statbus.org (3011 slot local, 3031 slot test), their auth cookies collide. Browsers scope cookies by host, not port, so both slots read and write the same 'statbus' and 'statbus-refresh' cookies (auth.extract_access_token_from_cookies reads cookies->>'statbus'), each slot signs with its own JWT secret, and signing in on one tab logs the other out. Observed: the owner was sent to /login on 3031 after each sign-in on 3011, and the ?next= path was lost. Fix: name the auth cookies per slot (e.g. statbus-<slot code> / statbus-<slot code>-refresh), so two slots on one host keep separate sessions; production has one slot per host, so the name change is invisible there apart from a one-time sign-in after the upgrade. Also check why /login drops ?next= after a rejected cookie.
<!-- SECTION:NOTES:END -->
