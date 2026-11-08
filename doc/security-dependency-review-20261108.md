# Application dependency security review, 2026-11-08

## Decision and release gate

STATBUS-593 applies compatible fixes for Next.js, Undici and DOMPurify, and bounds all current application-defined Zod query-array inputs before JSON decoding and schema traversal. The Zod advisory is **mitigated at these application boundaries, not patched or dismissed**. This work does **not** close all dependency advisories. The next stable release remains on the owner's **personal-review hard hold**. Local checks are not deployment authorization, CI evidence, or a substitute for the owner's review of the residual findings below.

No alerts were ignored or dismissed. No database, loader, cloud or deployment changes are part of this patch. The 23 open GitHub alert records supplied for this task predate this work and are not established STATBUS-591 regressions.

## Evidence and method

- Baseline: `tmp/591-current-dependency-alerts.tsv` and `tmp/591-current-dependency-advisories.tsv`, captured on 2026-11-08. The 23 records include duplicate manifest/lockfile alerts, including five critical records.
- Primary source: GitHub's global advisory REST API, `GET /advisories/{GHSA-ID}`. Every ID below has a preserved response at `tmp/593/{GHSA-ID}.json`. Use `https://github.com/advisories/{GHSA-ID}` for its public page.
- Registry evidence: `pnpm view` of the patched versions, engine requirements, Mermaid dependency ranges and the published Zod 3, minimatch 10, glob 10, KaTeX 0.16 and deepmerge versions. No patched compatible release was found for the residual lines below.
- Reproduction: `tmp/593/installed-before.json`, `why-before.txt`, `source-reachability.txt`, `audit-before.json` and `journal.md`. The audit exited 1. Its advisory aggregation reported 3 critical, 7 high, 7 moderate and 3 low findings, not the same counting unit as the 23 GitHub alert records.
- Safe regression: `regression-before.log` demonstrates real Undici fetch incorrectly accepting a body with a mismatched mixed-case SRI digest, and DOMPurify retaining a split shadow-root template expression. Both tests fail before the dependency changes and pass afterwards in `regression-after.log`. The HTTP server binds loopback only. No memory-exhaustion attack was run.
- Resulting graph: `tmp/593/installed-after.json` and `audit-after.json`. The latter still exits 1, with **0 critical, 1 high, 3 moderate and 2 low findings**, representing five unique advisory IDs. This is not a claim that GitHub has closed any alerts, because this commit has not been pushed.

## Applied dependency changes

| Package | Installed before | Minimum patched version | Resolved after | Decision |
| --- | --- | --- | --- | --- |
| next | 16.3.8 | 16.4.1 | 16.4.5 | Raise floor to `~16.4.1`, retaining major 16 and its patch range |
| eslint-config-next and Next plugin | 16.3.8 | aligned tooling | 16.4.5 | Keep official config aligned with Next |
| undici | 7.29.1 | 7.30.1 | 7.30.2 | Raise floor to `^7.30.1`, retaining major 7 |
| dompurify, through Mermaid | 3.4.16 | 3.4.17 | 3.4.17 | Raise existing override floor to `^3.4.17`, within Mermaid's declared `^3.3.3` range |

The lockfile selects current patches within these compatible lines rather than pinning the first security patch. jsdom 26.1.0 and its types 21.1.7 are development-only test dependencies, compatible with the local Node 22 runtime. They provide the DOM used by the sanitizer tests and do not become application runtime imports. No broad update, forced major override, or Zod 3-to-4 migration was performed.

## Primary advisory inventory

Ranges in this table are the primary API's npm ranges applicable to the installed major. Other supported major branches may have different fixes. The metadata's `first_patched_version` is used even where older narrative text still says no fix was available.

| GitHub alert records | Advisory | Package and exact affected range | Primary first patch | Reachability and disposition |
| --- | --- | --- | --- | --- |
| 720, 713 | GHSA-673q-mjm6-r5xr | next `>=16.0.0, <=16.4.0` | 16.4.1 | App Router runtime. Typed-array `use cache` RCE preconditions are not established by source search, but the framework is patched rather than relying on that observation. |
| 716, 712 | GHSA-2464-fhr4-w9xw | next `>=16.0.0, <=16.4.0` | 16.4.1 | Image optimization runtime. SVG optimization is not explicitly enabled in next.config.js. Patched regardless. |
| 715, 711 | GHSA-p3m5-59mp-jv5r | next `>=16.0.0, <=16.4.0` | 16.4.1 | Server Actions are used, including legal-unit and admin forms. Patched. |
| 719 | GHSA-cg2g-xh64-v4q7 | dompurify `>=3.4.4, <=3.4.16` | 3.4.17 | Browser Mermaid sanitization. The application does not configure shadow-root template evaluation. Patched and split-expression regression reproduced. |
| 718 | GHSA-mrv2-3pqr-j5jr | dompurify `<=3.4.16` | 3.4.17 | Browser diagram dependency. Application code does not install IN_PLACE detachment hooks. Patched. |
| 717 | GHSA-c6gr-qvv4-5v3f | dompurify `<=3.4.16` | 3.4.17 | Browser diagram dependency. Application does not request XHTML SMIL allowlisting. Patched. |
| 729 | GHSA-4w7w-5xrc-9h26 | undici `>=7.0.0, <7.30.1` | 7.30.1 | Server HTTP Agent is used in authentication refresh and auth_test. Cache interceptor cross-origin poisoning is not configured there. Patched. |
| 728 | GHSA-2m5v-pch6-74hx | undici `>=7.0.0, <7.30.1` | 7.30.1 | Authentication HTTP Agent makes TLS behavior relevant when configured for HTTPS. Patched. |
| 727 | GHSA-qrxm-fqhp-jwvm | undici `>=7.0.0, <7.30.1` | 7.30.1 | Agent transport TLS renegotiation denial of service. Patched. |
| 726 | GHSA-9fm3-97px-rjf6 | undici `>=7.0.0, <7.30.1` | 7.30.1 | Package contains affected WebSocket implementation. App's imported Agent path does not establish WebSocket exposure. Patched. |
| 725 | GHSA-55wc-3pg8-jfw6 | undici `>=7.15.0, <7.30.1` | 7.30.1 | Decompress interceptor is not configured in the two application imports. Patched. |
| 724 | GHSA-xjj6-f33q-929c | undici `>=7.18.0, <7.30.1` | 7.30.1 | HTTP content-encoding error handling. Patched. |
| 723 | GHSA-4qv8-2p9j-2685 | undici `>=7.0.0, <7.30.1` | 7.30.1 | EventSource parser is not imported by the application's Agent consumers. Patched. |
| 722 | GHSA-f72v-6w45-q472 | undici `>=7.15.0, <7.30.1` | 7.30.1 | Application does not currently pin SRI on Agent requests. Actual fetch integrity behavior reproduced and fixed. |
| 721, 714 | GHSA-mrhx-c7xc-m3w5 | zod `<4.6.6` | 4.6.6 | **Remaining, application query-array path mitigated**, 3.25.76. URL filter/sort parsers prebound raw JSON input, root arrays and nested filter arrays. Server FormData validation retains v3 contracts. See mitigation and owner gate below. |
| 733 | GHSA-g3hv-75wg-m249 | minimatch `>=7.0.0, <11.0.1` | 11.0.1 | **Remaining**, 10.2.5. ESLint/Jest and production ExcelJS archive dependencies share the existing override. See review gate. |
| 731 | GHSA-3g3m-2fjr-6pw4 | glob `>=9.0.0, <=14.0.1` | 14.0.2 | **Remaining**, 10.5.0 and 13.0.6. Jest, rimraf and ExcelJS archiver paths. Glob 7.2.3 is outside this advisory's affected range. See review gate. |
| 730 | GHSA-gcqx-w48m-w2h4 | deepmerge `>=4.2.0, <=4.3.1` | none | **Remaining**, 4.3.1. Jest configuration dependency, not application source import. See no-patch gate. |
| 697 | GHSA-238p-pmpm-9mq7 | katex `>=0.11.0, <0.18.2` | 0.18.2 | **Remaining**, 0.16.47, through Mermaid 11.16.1. Diagram dependency is client runtime. See review gate. |

Node's built-in global fetch also carries the Node runtime's own Undici implementation. Updating the npm Agent package does not prove that the deployed Node runtime is patched. The owner must review the runtime image separately before stable. Application source uses the npm Agent as dispatcher with global fetch, so the focused npm-fetch test is representative transport evidence, not an end-to-end authentication or deployed-runtime assertion.

## Remaining advisories: explicit owner review gates

These are unresolved findings, not accepted risks or false positives. The release owner must sign off personally before lifting the next-stable hold. If the owner does not approve a bounded interim mitigation, remediation is required before release.

1. **Zod, high, GHSA-mrhx-c7xc-m3w5, application query-array path mitigated.** The latest published 3.x is 3.25.76, and the first vendor fix is 4.6.6. `app/src/lib/parsers.ts` now rejects raw query input over 65,536 UTF-16 code units before `JSON.parse`, rejects non-array roots and roots over 128 items before Zod, and preflights every filter's array-valued `value` for the 256-item limit before either root or nested Zod array traversal. These guards cover all three application-defined `z.array` uses found in the source inventory. This bounds the query path's JSON allocation and per-element issue accumulation without a breaking Zod migration. It does not patch the installed package or dismiss the high alert. Server FormData schemas continue to use v3, with their existing scalar/date/coercion contracts tested. Third-party Zod internals and any future array entrypoint are not certified by this mitigation. Owner gate: review these resource budgets and the complete residual graph before stable, and require equivalent pre-parse/pre-traversal budgets for future untrusted array inputs until a separately reviewed v4 migration replaces Zod 3.
2. **minimatch, moderate, GHSA-g3hv-75wg-m249.** No published 10.x is outside the advisory range, including 10.2.6. 11.0.1 crosses a major boundary, and the existing project-wide override already affects legacy callers. Paths include ESLint, TypeScript tooling, Jest, readdir-glob and ExcelJS archiving, so calling it development-only would be incorrect. App workbook export uses its existing stream path, not a user-supplied glob API. Interim restriction: keep glob patterns repository-controlled and do not expose arbitrary wildcard input to these consumers. Owner gate: review minimatch 11 caller compatibility, run lint/test/build and ExcelJS export behavior before replacing the override. No claim is made that full-suite success alone proves all legacy glob APIs compatible.
3. **glob, moderate, GHSA-3g3m-2fjr-6pw4.** 10.5.0 is the latest published 10.x. 14.0.2 is a breaking major relative to 10 and 13. The advisory concerns AbortSignal cancellation failing to stop traversal. Jest project matching, rimraf clean commands and ExcelJS archive helpers are reachable dependency consumers. Interim restriction: only trusted repository paths/patterns, and no reliance on cancellation as a security boundary. Owner gate: upgrade the parent tooling/archive libraries to compatible patched glob consumers or explicitly validate a scoped override, including cancellation completion and workbook export. This patch does not force glob 14 into all callers.
4. **deepmerge, low, GHSA-gcqx-w48m-w2h4.** Latest registry release is 4.3.1 with no primary patched version. Dependency reachability is Jest config merging. Interim mitigation: execute test/configuration code only from trusted reviewed repositories, with untrusted PR jobs denied secrets and deployment credentials. This is an operating requirement, not a newly verified CI-policy change. Owner gate: verify those controls and choose an upstream fix, parent replacement, or a reviewed local patch with positive prototype/merge contract tests. Do not dismiss the alert or override to a differently named API without migration tests.
5. **KaTeX, low, GHSA-238p-pmpm-9mq7.** Mermaid 11.16.1 declares `^0.16.45`, resolving 0.16.47. 0.18.2 is outside that pre-1.0 compatible range. Mermaid 12.3.0 declares `^0.18.0`, but updating Mermaid's major is not a minimal compatible fix. The application renders a database-generated ER diagram, with Mermaid's default strict security configuration and without enabling KaTeX trust. That reduces the demonstrated path to the advisory's pre-existing prototype-pollution trust bypass, but does not remove the affected package. Owner gate: approve Mermaid 12 migration or a scoped KaTeX 0.18.2 compatibility update with real-browser ER and mathematical-label rendering plus prototype-pollution trust-boundary tests. Keep diagram input database-controlled and do not enable `trust` or loose security in the meantime.

## Bounded query-state mitigation

The limits are defined together at `queryStateLimits` in `app/src/lib/parsers.ts`, with their purpose documented at that definition:

- **65,536 UTF-16 code units, inclusive, per decoded query value.** The O(1) string-length check precedes `JSON.parse`. It leaves ample headroom for ordinary table state while bounding the initial JSON allocation. This is a JavaScript string-length budget, not a 64KiB UTF-8 or HTTP transport assertion. Unicode test fixtures intentionally have more UTF-8 bytes than code units.
- **128 root items, inclusive, for both sorting and filtering.** Non-arrays and excess item counts are refused immediately after bounded JSON decoding, before constructing validation issues for any row. This leaves substantial headroom beyond the handful of sort/filter controls typical of a table.
- **256 nested filter values, inclusive, per filter.** The preflight checks every root item before calling the root Zod schema, including a later filter after an earlier malformed row. This retains broad multi-select selections while bounding nested array issue accumulation. Raw and root limits apply simultaneously, so combining every individual maximum may exceed the total raw budget.

Over-budget state returns `null`, using the existing invalid-query contract rather than silently truncating selections. Within-budget serialization, parsing, equality and column allowlists are unchanged. The guards are outside Zod because `.max()` by itself would not establish early termination in the installed v3 validator.

`tmp/593/query-array-boundaries.txt` records the full source search: the root sorting array, root filtering array and filter `value` string array are the only current application-defined `.array()` schemas. Sorting's raw/root checks cover its boundary, and filtering's raw/root/nested checks cover both of its boundaries. Third-party packages have their own internals, so this inventory is not a claim about every array in the installed graph.

`app/src/lib/parsers.test.ts` uses the real application parser callbacks, real Zod and the actual Nuqs implementation loaded through Node's native ESM-capable loader. Small fixtures at and one item/code unit beyond each limit exercise accepted boundary roundtrips and refused oversize state, without an OOM workload. Instrumentation verifies raw refusal precedes `JSON.parse`, and root/nested refusal precedes `ZodArray._parse`. It also preserves scalar/multiselect/empty/date-range filters, allowlists as arrays and sets, malformed input refusal and ordinary schema validation.

The parent implementation produced **11 failing and 5 passing cases** before the guard change (`tmp/593/query-bounds-red.log`). All **16 cases pass** after it (`query-bounds-green.log`). Full frontend checks are rerun below. The dependency audit remains open because mitigation does not alter the vulnerable package version.

## Verification and limitations

`app/src/lib/dependency-security.test.ts` exercises:

- Real loopback Undici fetch accepting correct pinned bytes and rejecting incorrect bytes for lowercase, uppercase and mixed-case integrity tokens.
- Mermaid's actual resolved DOMPurify preserving SVG structure, label text and a safe hyperlink while producing the expected sanitized child tree.
- Split-expression shadow-root sanitization returning neutral text. This fails on 3.4.16 and passes on 3.4.17.
- Mermaid's actual ESM parser accepting the application's ER syntax with ELK front matter. This is parser compatibility, **not a full browser layout/rendering test**.
- The application's contact FormData schema preserving nullable source IDs, empty valid-to conversion, optional values and invalid-date issue paths on Zod 3.

Full frontend checks on the resulting graph, rerun after the query-bound mitigation (the initial 26-suite/213-test dependency-only results remain in the original logs):

| Check | Result | Evidence |
| --- | --- | --- |
| `pnpm run tsc` | PASS | `tmp/593/query-bounds-tsc.log` |
| `pnpm run lint` | PASS, 0 errors and 5 warnings | `tmp/593/query-bounds-lint.log`. Warnings are internal navigation and TanStack compiler compatibility, outside this dependency patch. |
| `pnpm exec jest --runInBand` | PASS, 27 suites and 229 tests | `tmp/593/query-bounds-tests.log` |
| `pnpm run build` | PASS, Next.js 16.4.5 production build | `tmp/593/query-bounds-build.log` |
| Advisory audit | FAIL, five unresolved unique IDs including the application-mitigated Zod finding | `tmp/593/query-bounds-audit.json`, six aggregated findings and zero critical |

The final formatted parser and test source passed Prettier, typecheck, lint, all 27 suites / 229 tests and production build again in `tmp/593/query-bounds-final-checks.log`. The package graph is unchanged by the query mitigation.

CI for the exact committed source is **not run in this worker**. Pushing is explicitly prohibited for this assignment. The coordinator owns shared-HEAD integration, final candidate checks and exact-SHA CI inspection after any authorized push. Record both GitHub Actions `status` and `conclusion` for that SHA before satisfying the ticket's CI acceptance criterion. No deployment or browser acceptance claim is made by these local checks.
