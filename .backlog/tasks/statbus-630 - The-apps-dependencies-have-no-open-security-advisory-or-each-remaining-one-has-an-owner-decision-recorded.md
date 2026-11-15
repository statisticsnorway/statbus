---
id: STATBUS-630
title: >-
  The app's dependencies have no open security advisory, or each remaining one
  has an owner decision recorded
status: In Progress
assignee: []
created_date: '2026-11-15T16:14:00Z'
updated_date: '2026-11-15T16:14:00Z'
labels:
  - security
  - app
dependencies: []
priority: high
type: chore
ordinal: 541204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Six Dependabot alerts remain open on master after STATBUS-593 (2026-11-15, gh api dependabot/alerts): zod GHSA-mrhx-c7xc-m3w5 high (721, 714; installed 3.25.76, fixed 4.6.6), minimatch GHSA-g3hv-75wg-m249 moderate (733; fixed 11.0.1), glob GHSA-3g3m-2fjr-6pw4 moderate (731; fixed 14.0.2), katex GHSA-238p-pmpm-9mq7 low (697; 0.16.47 via Mermaid 11, fixed 0.18.2, Mermaid 12 declares ^0.18), deepmerge GHSA-gcqx-w48m-w2h4 low (730; no fix, Jest config). STATBUS-593 bounded the Zod query-array path in app/src/lib/parsers.ts but left Zod 3. Each needs a major upgrade, so each is its own step with its own checks. Order: Zod 4 (21 source files, zod-form-data 2 -> 3, @hookform/resolvers already supports 4), minimatch/glob, KaTeX via Mermaid 12, then the owner decides on deepmerge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Zod 4.6.6 or later is the only zod in the app's graph; every form schema and the URL query parsers keep their accepted and refused inputs and error messages, shown by tests on the real schemas, and the frontend typecheck, lint, tests and build pass
- [ ] #2 minimatch and glob resolve to patched versions, and lint, Jest, rimraf and the Excel export still work, shown by their real runs
- [ ] #3 KaTeX resolves to 0.18.2 or later through Mermaid 12, and the ER diagram renders in the owner's browser
- [ ] #4 deepmerge: the owner's decision (accept as Jest-only, or replace) is recorded here
- [ ] #5 gh api dependabot/alerts lists no open alert, or only the ones with a recorded owner decision; CI is green on that SHA
<!-- AC:END -->
