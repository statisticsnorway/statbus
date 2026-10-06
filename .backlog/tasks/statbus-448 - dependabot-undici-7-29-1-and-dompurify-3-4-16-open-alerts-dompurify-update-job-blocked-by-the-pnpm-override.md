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

## Reviewed compatible updates, 2026-10-06 20:18 UTC

The owner approved source merge/push for normal CI at 20:17 UTC. The independently reviewed commit `52ef8436868e7cb0cc4f887968f34d2e02e2bdcb` is integrated on master as `84011c82d3c2b8f43a8ba9f8e7099e1592ee8a4d`. Only `app/package.json` and the generated `app/pnpm-lock.yaml` changed. Stable patch IDs and the complete non-backlog source match the reviewed commit. Proof: `tmp/448-reviewed-source-proof-20261006T2018.log`. This source approval does not waive the remaining findings or authorize a release or installation.

### Observed validation

- Resolved undici 7.29.1, direct and Next sharp 0.35.5, Mermaid DOMPurify 3.4.16, and Tailwind/PostCSS source-map-js 1.2.2. The source-map floor was added after observing that the first targeted-update prototype retained vulnerable 1.2.1. Pinned pnpm 10.28.1 is unchanged.
- Owned frozen install, typecheck, lint, corrected Jest invocation (10 suites / 56 tests), and production Next build passed on the eventual committed source. Five existing lint warnings remain. The initial malformed Jest invocation failed without running tests and is retained, not counted as a passing run.
- Actual Next PNG-to-WebP and benign SVG smoke passed with identical direct/Next sharp. This was macOS arm64 in-process evidence, not HTTP, Linux deployment or token-refresh acceptance.
- Independent exact-pin review returned MERGE: `tmp/448-compatible-patches-review.md`. Whole-lock, consumer resolution and source checks passed. Raw regenerated-lock comparison was not byte-identical: the two inspected differences are an already-existing compatible semver edge dedupe and unchanged-version ESLint registry metadata. Every other parsed field matched. The raw failure is retained.

### Remaining findings and boundaries

The recorded local audit fell from 17 findings to 3 and still exits 1: HIGH braces 3.0.3, MODERATE sprintf-js 1.0.3, and LOW KaTeX 0.16.47. No advisories are muted, no audit-zero claim is made, and no earlier exception is extended.

Published-parent investigation found no supported parent-only fix for sprintf-js or KaTeX. An expect update can remove one braces path, not all locked paths. No unsupported override, replacement test toolchain or vendored patch was introduced. Evidence: `tmp/448-parent-compatibility.md`.

Inspected braces patterns and sprintf formats originate in local tooling/parser configuration; an application HTTP input path was not established. KaTeX is present in the schema-derived client ER renderer, with early math and final strict-mode SVG sanitization. No controllable metadata/prototype-pollution chain or sanitizer bypass was demonstrated. Static inspection and the local packaging inventory are not deployed exploitability proof or a waiver. Evidence: `tmp/448-residual-exposure.md`.

### Acceptance status at integration

AC1 remains unmet because audit is not zero. AC2 awaits actual updated Dependabot results after the approved push. AC3 is partial: app gates passed, but real login, access-token expiry and refresh against an owned stack have not run. AC4 remains unmet: no zero-alert observation and no PR321 closure. The ticket stays open. Normal source CI on the new master SHA is pending; previous 619 gates do not transfer. No RC, production install, callback, alert dismissal or PR action occurred.
