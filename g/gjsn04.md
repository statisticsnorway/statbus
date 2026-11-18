---
id: "gjsn04"
title: >-
  A checkout's dev server gets its own port and its slot's Caddy serves it over
  HTTP/2
state: "done"
assignee: []
updated_date: '2026-11-16T13:06:00Z'
labels:
  - dev-tooling
group: ""
rank: "000000000599"
dependencies: []
priority: medium
origin: "backlog:STATBUS-624"
aliases: ["STATBUS-624"]
type: "feature"
created: "2026-11-11T19:21:00Z"
updated: "2026-11-16T13:06:00Z"
---

## Goal

Each development checkout's Caddy forwards pages to host.docker.internal:3000 (caddy/templates/development.caddyfile.tmpl), so every checkout's https site shows whichever dev server runs on 3000 (../statbus's), and `./dev.sh https on` cannot serve a second checkout's code. A second checkout then runs `next dev --experimental-https` on its own port: HTTP/1.1 only, so Firefox's six connections per host fill with the worker-status SSE streams of open tabs and pages hang (owner 2026-11-11 17:49); its certificate is a hand-copied 12 h Caddy leaf that expires (13:03 and 21:03 UTC the same day).

Design: the dev server port is part of the slot's port block (3000 + offset*10 + 7; slot 1 = 3017, test slot 3 = 3037), written to .env as APP_DEV_PORT. The development Caddyfile forwards to host.docker.internal:APP_DEV_PORT, then app:3000. `pnpm run dev` starts next dev on APP_DEV_PORT and prints the Caddy address. `./dev.sh https on` then gives each checkout HTTP/2 with Caddy's renewing local CA.

## Acceptance
- [x] #1 sb config generate writes APP_DEV_PORT = 3000 + offset*10 + 7 to .env, and the development Caddyfile forwards to host.docker.internal:<APP_DEV_PORT> (Go test)
- [x] #2 pnpm run dev starts next dev on APP_DEV_PORT and prints the address to open
- [x] #3 In the test checkout (offset 3), with ./dev.sh https on and pnpm run dev, https://test.statbus.org:3031 answers over HTTP/2 with this checkout's code, observed with curl --http2 and in Firefox
- [x] #4 doc/development-reference.md and DEVELOPMENT.md name the per-slot dev port

## Implementation Notes

2026-11-11 19:30 (Rabbit): Committed locally, NOT pushed (owner to decide): APP_DEV_PORT = slot offset+7 in .env, development Caddyfile forwards to host.docker.internal:APP_DEV_PORT, pnpm run dev (app/scripts/dev.mjs) starts next dev on it. RED tmp/623-red.log (build fails: no AppDevPort), GREEN tmp/623-green.log (3 tests + whole config package). Observed in this checkout: .env APP_DEV_PORT=3037, Caddy route host.docker.internal:3037, pnpm run dev listened on 3037, https://test.statbus.org:3031 answered HTTP/2 200 through Caddy. Two local blockers kept AC3 from finishing: test.statbus.org has no DNS record (local.statbus.org -> 127.0.0.1 has), so the browser cannot open the slot's site; this slot's SERVER_REST_URL is http://proxy:80, which a host dev server cannot resolve (getaddrinfo ENOTFOUND proxy). Restored BROWSER_REST_URL=http://localhost:3013 afterwards. Open for owner: the local slot's dev server moves from 3000 to 3017.

2026-11-16: landed on master on top of d28df2738 (cherry-picked from d6dbc04bb). AC#1: go test ./internal/config ok (tmp/624-go-test-2.log). AC#2: in statbus_test (slot offset 3) pnpm run dev starts next dev on APP_DEV_PORT 3037 and prints 'Open the app at: https://local.statbus.org:3031/' (tmp/pnpm-run-dev.log). AC#3: after ./dev.sh https on, curl --http2 https://local.statbus.org:3031/login gives http_version 2, code 200, and the owner signed in in Firefox at 13:05. SITE_DOMAIN for the test checkout is local.statbus.org (owner 2026-11-16), so no /etc/hosts entry is needed; the criterion's test.statbus.org was the earlier plan. AC#4: doc/development-reference.md (Local https) and doc/DEVELOPMENT.md (Development Server, Access, API request flow) name APP_DEV_PORT = 3000 + offset*10 + 7. This replaces the hand-made 3007 proxy and copied certificate used during the 628 review.
