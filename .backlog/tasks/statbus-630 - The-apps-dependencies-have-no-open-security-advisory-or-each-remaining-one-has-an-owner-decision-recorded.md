---
id: STATBUS-630
title: >-
  The app's dependencies have no open security advisory, or each remaining one
  has an owner decision recorded
status: In Progress
assignee: []
created_date: '2026-11-15T16:14:00Z'
updated_date: '2026-11-15T22:57:00Z'
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
- [x] #1 Zod 4.6.6 or later is the only zod in the app's graph; every form schema and the URL query parsers keep their accepted and refused inputs and error messages, shown by tests on the real schemas, and the frontend typecheck, lint, tests and build pass
- [x] #2 minimatch and glob resolve to patched versions, and lint, Jest, rimraf and the Excel export still work, shown by their real runs
- [ ] #3 KaTeX resolves to 0.18.2 or later through Mermaid 12, and the ER diagram renders in the owner's browser
- [ ] #4 deepmerge: the owner's decision (accept as Jest-only, or replace) is recorded here
- [ ] #5 gh api dependabot/alerts lists no open alert, or only the ones with a recorded owner decision; CI is green on that SHA
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15 AC1 (Zod 4) landed in 7c9f5d360: zod 3.25.76 -> 4.6.7, zod-form-data 2.0.8 -> 3.0.4; pnpm why zod shows only 4.6.7 (eslint-plugin-react-hooks deduped onto it). app/src/lib/form-schemas.test.ts (22 tests) pins every edit and admin form's accepted values, written rows and refusal messages: written and green on Zod 3 first, then green on Zod 4. Message wording changed only for enum values the forms' own selects cannot send. Jest 353/353, tsc, lint (0 errors), production build pass locally. CI on 7c9f5d360, all completed/success: Fast Tests 43735971497, app build & lint 43735486971, Go Test 43735487200, Images 43735486899, Harness 43735486954, Push on master 43735487148, Notify 43735487043. Not yet seen in a browser: the local sign-in uses the owner's own accounts.

2026-11-15 AC2 (minimatch, glob) landed in ddb44cecb. No parent release moves archiver-utils (glob ^10) or Jest (glob ^13) onto the fixed majors, so scoped pnpm overrides lift only the vulnerable lines: minimatch@>=7 <11.0.1 -> ^11.0.8, glob@>=9 <14.0.2 -> ^14.0.6. Consumers checked in node_modules: they call only new Minimatch()/.match(), minimatch(), glob.sync/globSync, all present in 11/14. Moving off the project-wide minimatch ^10 override exposed ESLint's minimatch 3 to the project-wide brace-expansion ^5 override ('expand is not a function'); brace-expansion is now overridden per major to each line's fixed release (1.1.22, 2.1.8, 5.0.12). Installed now: minimatch 3.1.5/5.1.9 (below the advisory range) and 11.0.8; glob 7.2.3 (below range) and 14.0.6. New test: the streamed workbook the import download writes (archiver, zip-stream, readdir-glob, glob) reads back with values and types. Jest 354/354, tsc, lint 0 errors, build, rimraf run. pnpm audit: katex low, deepmerge low. CI on ddb44cecb all success: Fast Tests 43770503969, app build & lint 43770066993, Go Test 43770067037, Images 43770067079, Harness 43770067016, Push on master 43770065915, Notify 43770067017.
2026-11-15 AC3 (KaTeX via Mermaid 12) on branch statbus-630-mermaid12 (a97cad00f), NOT on master, waiting for the owner to see the diagram: mermaid 12.3.0, katex 0.18.10. The ER page sets layout dagre, theme default, look classic. Finding: the page asked for ELK, but Mermaid 11 had no ELK loader and drew with dagre. Real ER diagram (generate_mermaid_er_diagram, 68 KB, ~270 tables) drawn in Firefox: Mermaid 11 41 s; Mermaid 12 + ELK 175 s, colours and layout changed; Mermaid 12 pinned to dagre/default/classic 84 s, same look and same 49995x8200 SVG as Mermaid 11. Before/after pages in tmp/630/mermaid/ (m11.html, m12.html, m12-classic.html; served with python3 -m http.server from that directory). Jest 354/354, tsc, lint, build pass on the branch; audit leaves only deepmerge.
<!-- SECTION:NOTES:END -->
