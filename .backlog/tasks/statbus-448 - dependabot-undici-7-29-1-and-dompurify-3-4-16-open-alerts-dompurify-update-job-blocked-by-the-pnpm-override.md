---
id: STATBUS-448
title: >-
  dependabot: undici 7.29.1 and dompurify 3.4.16 open alerts; the dompurify
  update job is blocked by our pnpm override
status: To Do
assignee: []
created_date: '2026-10-05 18:12'
labels:
  - security
  - dependencies
  - app
dependencies: []
references:
  - STATBUS-363
priority: medium
---

## Issue

Since 2026-09-29/10-01, master has 11 open Dependabot alerts on `app/pnpm-lock.yaml`:

- **undici 7.29.0, fixed in 7.29.1:** 10 alerts (2 high, 5 medium, 3 low).
  - High: a TLS certificate validation bypass via a dropped connection (#687), and DoS via an unrequested WebSocket subprotocol (#691).
  - The rest: cookie disclosure via Set-Cookie caching, response splitting in the retry interceptor, decompression DoS, WebSocketStream DoS, and similar.
  - Dependabot PR #321 (7.29.0 → 7.29.1) is open.
- **dompurify 3.4.14, fixed in 3.4.16:** 1 low alert (#694): with `IN_PLACE`, a node-removing `afterSanitize` hook leaves a detached node.

The Dependabot security update job for dompurify fails on every push to master (for example run 37350875945 at 7cf1cfe5a): "The latest possible version of dompurify that can be installed is 3.4.14". dompurify is only a transitive dependency (via mermaid 11.16.1), and our `package.json` `pnpm.overrides` pins `"dompurify": "^3.4.0"`. Dependabot runs `pnpm update dompurify@3.4.16 --lockfile-only --no-save -r`, which does not move an overridden transitive dependency, so the job can never succeed until the override itself is raised.

## Reachability triage (2026-10-05 18:12, read-only)

- **undici:**
  - The app imports it only for `Agent` (`app/src/utils/auth/server.ts`, `app/src/app/api/auth_test/route.ts`), with `connect: { timeout: 5000 }`.
  - The only target is `SERVER_REST_URL`, which `docker-compose.app.yml` hardcodes to `http://proxy:80`: plain HTTP to our own Caddy on the internal network.
  - No TLS, no WebSocket, no cache or retry interceptors, and no third-party origin.
  - The two high alerts need TLS (#687) or WebSocket (#691) and are not reachable. Next.js's bundled fetch is separate from this dependency.
- **dompurify:** mermaid's ESM chunks call `purify.sanitize(...)` and add `beforeSanitizeAttributes` and `afterSanitizeAttributes` hooks, but never pass `IN_PLACE: true` (0 occurrences). The alert requires `IN_PLACE`, so it is not reachable.

Conclusion: nothing is exploitable in the deployed app. Per the STATBUS-363 owner ruling, dependency bumps stay out of the in-flight release candidate (v2026.10.0-rc.15, which carries the STATBUS-447 demo repair). This lands in the next batch.

## Work

1. In `app/package.json`, raise `undici` to `^7.29.1` and the `pnpm.overrides` entry for `dompurify` to `^3.4.16`.
2. Run `pnpm install`, then check that the lockfile resolves undici 7.29.1 and dompurify 3.4.16.
3. Validate: `pnpm run tsc`, `pnpm run lint`, `pnpm run test`, `pnpm run build`, and `pnpm audit` (expect 0).
4. Smoke the token refresh path (`refreshAuthToken`) against a running stack: login, let the access token expire, and confirm a page load refreshes it.
5. Close PR #321 as superseded.

## Acceptance criteria
<!-- AC:BEGIN -->
- [ ] #1 The lockfile resolves undici >= 7.29.1 and dompurify >= 3.4.16, and `pnpm audit` reports 0 vulnerabilities.
- [ ] #2 The Dependabot dompurify security update job stops failing on pushes to master (no override pins it below the patched version).
- [ ] #3 The app tests, typecheck, lint and build pass, and a token refresh works end to end against a running stack.
- [ ] #4 GitHub shows 0 open Dependabot alerts for `app/pnpm-lock.yaml`, and PR #321 is closed.
<!-- AC:END -->
