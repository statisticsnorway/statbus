---
id: STATBUS-448
title: >-
  Open Dependabot alerts on app/pnpm-lock.yaml are resolved or recorded as
  having no fix
status: In Progress
assignee: []
created_date: '2026-10-05 18:12'
updated_date: '2026-10-17 16:13'
labels:
  - security
  - dependencies
  - app
dependencies: []
references:
  - STATBUS-363
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The app ships no dependency with a known, fixable vulnerability.

### Zoom out
Dependabot raises alerts against app/pnpm-lock.yaml. A fixable alert is fixed by resolving the patched version; one with no published fix is recorded with its reason. The ticket's original pair (undici 7.29.1, dompurify 3.4.16) is already resolved in the lockfile.

### Zoom in (2026-10-17, 11 open alerts)
- **next 16.3.6:** 1 high and 5 medium (701-706), fixed in 16.3.8. A production dependency.
- **handlebars 4.7.9:** 2 critical and 1 medium (708-710), fixed in 4.7.10. Dev-only, through ts-jest; package.json overrides it to ^4.7.9.
- **katex 0.16.47:** 1 low (697), fixed in 0.18.2. Comes in through mermaid 11.16.1, which pins the 0.16 line; a jump of two minor versions.
- **sprintf-js 1.0.3:** 1 medium (699), no patched version published.

### Closing review
- **Memory:** none. **Documentation:** none. **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The lockfile resolves next >= 16.3.8 and handlebars >= 4.7.10
- [x] #2 The app tests, typecheck, lint and build pass with the bumped lockfile
- [x] #3 The alerts with no published fix (sprintf-js), and any left on purpose (katex through mermaid), are recorded in Implementation Notes with the reason
- [ ] #4 After the push, GitHub shows the next and handlebars alerts as fixed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Fix (feee6f62f, 2026-10-17)
- next ~16.3.8 (and eslint-config-next ~16.3.8), pinned to the 16.3 patch line. The caret range resolved 16.4.2, a minor release with more change than this security fix needs. The handlebars override is now ^4.7.10. The lockfile resolves next 16.3.8, eslint-config-next 16.3.8 and handlebars 4.7.10.
- **Locally:** pnpm install --frozen-lockfile, tsc, lint, the app tests (24 suites, 202 tests) and pnpm run build all pass.
- **Left, with reason:** katex 0.16.47 (alert 697, low) comes through mermaid 11.16.1, which requires the 0.16 line. Moving to 0.18.2 means overriding a dependency of mermaid across two minor versions, which needs its own check of mermaid diagrams. sprintf-js 1.0.3 (alert 699, medium) has no patched version published.
- Waiting: GitHub marks alerts 701-706 and 708-710 fixed after the push.
<!-- SECTION:NOTES:END -->

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

## Fresh read-only inventory, 2026-10-06 15:38 UTC

The actual GitHub alert API now returns 16 open alerts for `app/pnpm-lock.yaml`: 4 high, 6 medium and 6 low. Raw selected metadata is retained in `tmp/448-open-alerts-20261006T1538.jsonl`. The prior 11-alert reachability triage is not evidence about these five additional alerts:

| Alert | Package | Severity | Advisory | First patched version |
| --- | --- | --- | --- | --- |
| 700 | sharp | high | GHSA-wq5f-xc86-pv6w, librsvg dependency CVE-2026-96889 | 0.35.5 |
| 699 | sprintf-js | medium | GHSA-hp3w-g68c-fv3c, unbounded precision denial of service | none reported |
| 698 | dompurify | low | GHSA-6688-9rhm-gjv2, IN_PLACE rawtext-root reparse | 3.4.16 |
| 697 | katex | low | GHSA-238p-pmpm-9mq7, prior prototype pollution bypasses trust restrictions | 0.18.2 |
| 696 | source-map-js | high | GHSA-68fv-2mgg-jv7q, indexed source-map offset denial of service | 1.2.2 |

The existing 10 undici alerts and dompurify alert694 remain open. Current dompurify, katex and source-map-js Dependabot update runs failed separately from the product CI. This inventory is not a new exploitability assessment, `pnpm audit`, dependency fix or extension of the owner's STATBUS-363 exception. A bounded source-reachability review of the additional alerts is required before claiming the same exception applies. No dependencies, lockfile, installation, PR or security-alert state changed.
