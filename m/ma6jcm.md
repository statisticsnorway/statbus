---
id: "ma6jcm"
title: A dev checkout's generated addresses follow its slot
state: "todo"
assignee: ["rabbit"]
updated_date: '2026-11-16T13:53:00Z'
labels:
  - dev-tooling
group: ""
rank: "000000000606"
dependencies: []
priority: high
type: "bug"
origin: "backlog:STATBUS-631"
aliases: ["STATBUS-631","development-checkout-s-generated"]
backlog_type: "bug"
created: "2026-11-16T13:10:00Z"
updated: "2026-11-16T13:53:00Z"
model: "claude-opus-5-5"
branch: "statbus-628-all-forms"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
A development checkout's generated addresses follow its slot, so a stale value can't send the dev server to another slot, and two slots on one host keep separate sign-ins.

## Purpose
The test checkout still held SERVER_REST_URL=http://proxy:80 and STATBUS_URL=http://localhost:3013 from an earlier setup: the host dev server's auth check failed with ENOTFOUND proxy on every request, and the page reloaded to /login in a loop (owner 2026-11-16 13:06). BROWSER_REST_URL pointed at another slot's REST (localhost:3013). Each new checkout or reboot repeats the diagnosis.

## Principle
In development the addresses are derived from SITE_DOMAIN and the slot, not remembered; a value that differs is an explicit operator override, never a leftover.

## Relevant details
In development, sb config generate derives STATBUS_URL, BROWSER_REST_URL and SERVER_REST_URL from SITE_DOMAIN, the slot's ports and DEV_HTTPS (declared in .env.config, default true; https://<domain>:<CADDY_HTTPS_PORT> or http://<domain>:<CADDY_HTTP_PORT>). They are written to .env only. ./dev.sh https on/off sets DEV_HTTPS and regenerates. On first run, config generate drops the three address lines from .env.config and sets DEV_HTTPS from the old BROWSER_REST_URL scheme. Cookie names stay fixed; each slot on a machine has its own SITE_DOMAIN, checked through the proxy container label org.statbus.site_domain in every mode by config generate and sb start.

## Acceptance
- [ ] In development, after sb config generate, SERVER_REST_URL, STATBUS_URL and BROWSER_REST_URL in .env name this checkout's SITE_DOMAIN and slot ports (Go test with a .env.config holding http://proxy:80 and another slot's port)
- [ ] ~~pnpm run dev refuses to start, naming the key and the expected value, when .env still holds an address the dev server can't reach~~ (not relevant: addresses are derived on every config generate and never remembered, so no stale value can reach the dev server (owner 2026-11-18), rabbit, 2026-11-18)
- [ ] ~~In the test checkout, a fresh pnpm run dev after ./dev.sh https on signs in at https://local.statbus.org:3031 without hand edits~~ (not relevant: wrong domain: the test checkout is test.statbus.org; replaced by a check on https://test.statbus.org:3031, rabbit, 2026-11-18)
- [ ] ~~Two slots on the same host (local.statbus.org:3011 and :3031) stay signed in side by side: signing in on one leaves the other signed in (observed in Firefox)~~ (not relevant: owner 2026-11-18 kept fixed cookie names (4b4dc87f9): one domain per slot instead; replaced by the duplicate-domain check, rabbit, 2026-11-18)

## Notes
Owner 2026-11-16 13:45, the second half of this ticket: since both checkouts use SITE_DOMAIN=local.statbus.org (3011 slot local, 3031 slot test), their auth cookies collide. Browsers scope cookies by host, not port, so both slots read and write the same 'statbus' and 'statbus-refresh' cookies (auth.extract_access_token_from_cookies reads cookies->>'statbus'), each slot signs with its own JWT secret, and signing in on one tab logs the other out. Observed: the owner was sent to /login on 3031 after each sign-in on 3011, and the ?next= path was lost. Fix: name the auth cookies per slot (e.g. statbus-<slot code> / statbus-<slot code>-refresh), so two slots on one host keep separate sessions; production has one slot per host, so the name change is invisible there apart from a one-time sign-in after the upgrade. Also check why /login drops ?next= after a rejected cookie.

2026-11-16 13:52: first part landed on master 6062126dd. app/next.config.js no longer hard-codes local.statbus.org: allowedDevOrigins and the dev proxy address use the slot's SITE_DOMAIN. Before it, the test slot on test.statbus.org:3031 loaded forever ('Blocked cross-origin request to /_next/hmr from test.statbus.org'). Check: tmp/next-config-origin-check.log (local, test and empty domain give their own origin; empty falls back to local.statbus.org); headless sign-in and page load on https://test.statbus.org:3031 (tmp/test-slot-peek.log); no 'Blocked cross-origin' in tmp/pnpm-run-dev.log. The test checkout's SITE_DOMAIN is test.statbus.org again, with an /etc/hosts entry (owner), so its cookies are its own. Remaining: config generate keeping the slot-derived addresses current (AC#1-#3), and per-slot cookie names.

2026-11-18 13:26 (Rabbit): paused for 50bwaz (reset + factory defaults, owner's detour for the next rc); the owner's open question here comes right after it.

2026-11-18 20:28 owner decisions (question 1): in development, sb config generate derives STATBUS_URL, BROWSER_REST_URL and SERVER_REST_URL from SITE_DOMAIN, the slot's ports and one flag in .env.config: DEV_HTTPS (default true). DEV_HTTPS=true gives https://<domain>:<CADDY_HTTPS_PORT>, false gives http://<domain>:<CADDY_HTTP_PORT>; SERVER_REST_URL follows BROWSER_REST_URL. The three addresses are written to .env only, never read from .env.config in development. ./dev.sh https on/off sets DEV_HTTPS and regenerates (https trust once per machine). Migration of a checkout: config generate removes the three address lines from .env.config (as it already removes the legacy DB_MEM_LIMIT line) and sets DEV_HTTPS from the old BROWSER_REST_URL scheme. No address override until someone needs one. Standalone unchanged. Context: statbus (slot local) has STATBUS_URL :3000, stale since per-slot dev ports; statbus_test once held http://proxy:80 and another slot's port. Question 2 (per-slot cookie names) still open.

2026-11-18 20:44 owner decisions (question 2): cookie names stay fixed ('statbus', 'statbus-refresh'), as the owner chose on 2025-04-10 in 4b4dc87f9 ('Each installation is on it's own domain'). The rule is one SITE_DOMAIN per slot on a machine. Detection: docker-compose.yml labels the proxy service org.statbus.site_domain=${SITE_DOMAIN}; sb config generate and sb start stop with a clear message when a running container from another compose project carries the same domain label. This applies in every deployment mode (harmless in standalone, catches double routing on a cloud host). Only running slots are seen, which is the case where sign-ins collide.
