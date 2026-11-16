---
id: STATBUS-630
title: >-
  The app's dependencies have no open security advisory, or each remaining one
  has an owner decision recorded
status: In Progress
assignee: []
created_date: '2026-11-15T16:14:00Z'
updated_date: '2026-11-16T13:42:00Z'
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
## North Star
The app ships with no known security advisory in its dependencies, and any it keeps is a decision the owner made and wrote down.

## Zoom out
Six Dependabot alerts were open on master after STATBUS-593 (2026-11-15). Each fix needed a new major version of a library, so each is its own step with its own checks, and the visible ones are checked by the owner before they land.

## Zoom in
- zod GHSA-mrhx-c7xc-m3w5, high (alerts 721, 714): Zod 3.25.76 -> 4.6.7 with zod-form-data 3 (7c9f5d360).
- minimatch GHSA-g3hv-75wg-m249 and glob GHSA-3g3m-2fjr-6pw4, moderate (733, 731): scoped pnpm overrides lift only the vulnerable lines to minimatch 11 / glob 14; no parent release does (ddb44cecb).
- katex GHSA-238p-pmpm-9mq7, low (697): Mermaid 11 -> 12, KaTeX 0.18.10; the ER page keeps today's look (d28df2738, owner 2026-11-16).
- deepmerge GHSA-gcqx-w48m-w2h4, low (730): no fixed release exists; only Jest's configuration merging uses it. Owner decides.
- Follow-up raised by the owner: the ER diagram is slow to draw (41 s today, 84 s on Mermaid 12 with today's look). A faster diagram is a separate project, to discuss later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Zod 4.6.6 or later is the only zod in the app's graph; every form schema and the URL query parsers keep their accepted and refused inputs and error messages, shown by tests on the real schemas, and the frontend typecheck, lint, tests and build pass
- [x] #2 minimatch and glob resolve to patched versions, and lint, Jest, rimraf and the Excel export still work, shown by their real runs
- [ ] #3 KaTeX resolves to 0.18.2 or later through Mermaid 12, and the ER diagram renders in the owner's browser
- [x] #4 deepmerge: the owner's decision (accept as Jest-only, or replace) is recorded here
- [ ] #5 gh api dependabot/alerts lists no open alert, or only the ones with a recorded owner decision; CI is green on that SHA
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15 AC1 (Zod 4) landed in 7c9f5d360: zod 3.25.76 -> 4.6.7, zod-form-data 2.0.8 -> 3.0.4; pnpm why zod shows only 4.6.7 (eslint-plugin-react-hooks deduped onto it). app/src/lib/form-schemas.test.ts (22 tests) pins every edit and admin form's accepted values, written rows and refusal messages: written and green on Zod 3 first, then green on Zod 4. Message wording changed only for enum values the forms' own selects cannot send. Jest 353/353, tsc, lint (0 errors), production build pass locally. CI on 7c9f5d360, all completed/success: Fast Tests 43735971497, app build & lint 43735486971, Go Test 43735487200, Images 43735486899, Harness 43735486954, Push on master 43735487148, Notify 43735487043. Not yet seen in a browser: the local sign-in uses the owner's own accounts.

2026-11-15 AC2 (minimatch, glob) landed in ddb44cecb. No parent release moves archiver-utils (glob ^10) or Jest (glob ^13) onto the fixed majors, so scoped pnpm overrides lift only the vulnerable lines: minimatch@>=7 <11.0.1 -> ^11.0.8, glob@>=9 <14.0.2 -> ^14.0.6. Consumers checked in node_modules: they call only new Minimatch()/.match(), minimatch(), glob.sync/globSync, all present in 11/14. Moving off the project-wide minimatch ^10 override exposed ESLint's minimatch 3 to the project-wide brace-expansion ^5 override ('expand is not a function'); brace-expansion is now overridden per major to each line's fixed release (1.1.22, 2.1.8, 5.0.12). Installed now: minimatch 3.1.5/5.1.9 (below the advisory range) and 11.0.8; glob 7.2.3 (below range) and 14.0.6. New test: the streamed workbook the import download writes (archiver, zip-stream, readdir-glob, glob) reads back with values and types. Jest 354/354, tsc, lint 0 errors, build, rimraf run. pnpm audit: katex low, deepmerge low. CI on ddb44cecb all success: Fast Tests 43770503969, app build & lint 43770066993, Go Test 43770067037, Images 43770067079, Harness 43770067016, Push on master 43770065915, Notify 43770067017.
2026-11-15 AC3 (KaTeX via Mermaid 12) on branch statbus-630-mermaid12 (a97cad00f), NOT on master, waiting for the owner to see the diagram: mermaid 12.3.0, katex 0.18.10. The ER page sets layout dagre, theme default, look classic. Finding: the page asked for ELK, but Mermaid 11 had no ELK loader and drew with dagre. Real ER diagram (generate_mermaid_er_diagram, 68 KB, ~270 tables) drawn in Firefox: Mermaid 11 41 s; Mermaid 12 + ELK 175 s, colours and layout changed; Mermaid 12 pinned to dagre/default/classic 84 s, same look and same 49995x8200 SVG as Mermaid 11. Before/after pages in tmp/630/mermaid/ (m11.html, m12.html, m12-classic.html; served with python3 -m http.server from that directory). Jest 354/354, tsc, lint, build pass on the branch; audit leaves only deepmerge.

2026-11-16 owner (13:00): merge Mermaid 12 with today's look; the diagram is still slow, a faster one is a separate project to discuss later. Landed on master as d28df2738 (cherry-pick of the reviewed branch commit a97cad00f onto cdfc31bb3, no conflicts); branch statbus-630-mermaid12 deleted. Rechecked on master: katex 0.18.10, Jest 354/354, tsc pass, pnpm audit leaves only deepmerge (low). AC3's second half (the ER diagram in the owner's browser on the real /doc/er page) still to see; the side-by-side render of the real diagram is in tmp/630/mermaid.

2026-11-16 AC4 owner decision (13:05): accept deepmerge GHSA-gcqx-w48m-w2h4 (low) as dev-only. No fixed release exists; pnpm why deepmerge shows it only under jest -> jest-config (devDependencies), not in production dependencies or images. Dependabot alert 730 dismissed as tolerable_risk with that reason. gh api dependabot/alerts now lists no open alert.

2026-11-16 CI for the Mermaid merge d28df2738: app build & lint 43871800240 success (the workflow that lints, type-checks, runs Jest and builds the app), plus Go Test 43871800346, Images 43871800541, Harness 43871800419, Push on master 43871800087, Notify 43871800142 all success. Fast Tests runs the SQL suite against the database and does not exercise the app's dependencies, so it is not the gate for this change (owner 13:25).

2026-11-16 correction (owner 13:41): the ER page on the real app draws in about 5-8 s on Mermaid 12 (dev server log: GET /doc/er 200 in 5.1 s, then the draw; owner's eye ~8 s). The 41 s / 84 s / 175 s I reported came from a standalone test page that loaded Mermaid's whole ESM build chunk by chunk from a local file server, not from the app's bundle: wrong as a measure of the app, and not grounds for 'still slow'. The owner's earlier ~5 s was the old app container (Mermaid 11), since no dev server ran for this checkout after the crash.
<!-- SECTION:NOTES:END -->
