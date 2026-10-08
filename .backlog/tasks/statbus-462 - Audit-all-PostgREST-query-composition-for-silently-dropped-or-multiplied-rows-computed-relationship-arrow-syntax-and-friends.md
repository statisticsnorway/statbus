---
id: STATBUS-462
title: >-
  Audit all PostgREST query composition for silently dropped or multiplied rows
  (computed-relationship arrow syntax and friends)
status: Done
assignee: []
created_date: '2026-10-08 11:34'
updated_date: '2026-10-08 11:45'
labels:
  - app
  - data-model
dependencies: []
priority: high
ordinal: 389204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: we know that one PostgREST construct silently drops rows, and we do not know how many other places still use it. Find every place in the app where a query can silently lose or multiply rows, fix any live instance, and add a guard so the known-bad construct cannot come back unnoticed.

ORIGIN (STATBUS-421, verified by measurement): the search export select projected three computed relationships with arrow syntax, for example primary_activity_category_name:primary_activity_category->>name. Those names are functions that return SETOF (public.primary_activity_category(statistical_unit) RETURNS SETOF activity_category STABLE ROWS 1, likewise secondary_activity_category and physical_region). PostgreSQL evaluates set-returning functions in a select list in lockstep, so a row produces NO output row when all of them return an empty set. On the Norway dump that silently dropped 29,470 of 1,976,463 rows. The fix is PostgREST's spread syntax for to-one relationships, for example primary_activity_category(primary_activity_category_name:name).

WHAT TO DO.
1. INVENTORY: find every PostgREST query in the app (app/src, all select lists, embeds, filters and RPC calls) and for each one decide whether it can silently drop or multiply rows. Constructs to look for at minimum: arrow syntax applied to a computed relationship (the known-bad one), arrow syntax on any to-many embed, ?select with a spread over a to-many relationship, !inner joins that filter parent rows, aggregate or RPC endpoints whose row semantics differ from the count you would expect, and any place where a client-side count is compared to a server total. For each hit state file and line, what it does, and whether it can lose rows. Note the coordinator's earlier scope check: today the arrow-on-computed-relationship form exists only in app/src/app/search/export/export-query.ts, so treat anything else you find as new information.
2. FIX any live instance that can lose rows, with a test.
3. GUARD: add a regression check that the composed select lists (starting with the export select) do not use the known-bad construct, because a silently short result is invisible in normal use. Frame it as a real invariant on the query we send, not a grep for a token: the test should compose the select and assert the construct is absent.
4. DOCUMENT the rule where the next author will read it, so the distinction between '->>name' and 'relationship(alias:name)' is not lost again.

OUT OF SCOPE: the transport redesign of STATBUS-421 (the COPY route). This ticket is about finding and preventing silent row loss in query composition.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An inventory exists of every PostgREST query in app/src with, for each, a verdict on whether it can silently drop or multiply rows, with file and line references and the construct named.
- [x] #2 Every live instance that can lose rows is fixed, with a test that would have caught it.
- [x] #3 A regression check asserts that the composed export select does not use a computed-relationship arrow projection, framed as an invariant on the query we send rather than a grep for a token.
- [x] #4 The distinction between arrow syntax on a computed relationship and spread syntax for a to-one relationship is documented where query authors will see it.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The inventory states explicitly whether any hit beyond the export select exists today, so the scope of the class of bug is known rather than assumed.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner decision 2026-10-08 after the STATBUS-421 root cause: someone other than the export author should check whether this bites other places, as its own backlog item. The CSV column-order consequence of the Phase 1 fix needs no action, because the design is being replaced by the COPY route where column order is explicit.

AUDIT COMPLETE (2026-10-08): 198 executable PostgREST request templates inventoried (176 fluent: 106 reads, 40 mutations, 30 RPCs, plus 22 raw request templates). Complete per-site file/line/query/verdict inventory and evidence: tmp/462-postgrest-query-audit.md, with durable copy doc/postgrest-query-audit.md. No affected site beyond the export select exists today. The sole historical affected template had three unsafe arrow projections, already fixed by 7d89a032a, so 0 additional production row-loss fixes were necessary. Two !inner sites are intentional or PK/FK-guaranteed. All computed embeds are genuinely PK-bounded to-one relationships. No to-many arrow/spread or direct aggregate-select query exists. RPC counting units, temporal slices, count-only HEADs, pages and count consumers are documented.
REAL-STACK EVIDENCE: old three-arrow select returned 0 rows against its own exact 29,470 total on the all-relationships-empty cohort. Current composed select returned 29,470/29,470. Full composed Norway export returned 1,976,463/1,976,463 (426,331,946 bytes, 20.136 s). Stored JSON arrows returned 29,470/29,470, history embeds 1/1, import inner/outer embeds each 4/4, stats RPC deliberately returned a legal unit plus its enterprise, 2/2. Scalar upgrade computed fields were inspected from doc/db, but their live probe is blocked by the old artifact lacking public.upgrade (404/PGRST205), explicitly recorded, no schema changes made.
GUARD/DOC: added five parameterized invariants on composeExportSearchParams output, each with empty and populated dynamic definitions. All actual arrow roots must be stored external_idents/stats_summary JSON and all three to-one spreads must be retained, including replacement of an inherited unsafe select. Prototype demonstrated detection of physical_region->>code, not just the historical name token. Documented arrow/embed/spread distinction, actual to-one guarantees, intentional !inner and response-specific exact totals adjacent to PostgREST API guidance in .claude/rules/frontend.md.
VALIDATION: focused export suite 26/26 passed. Required app gates pnpm run tsc and pnpm run lint passed (0 errors, 5 existing warnings), pnpm test passed all 18 suites/131 tests. Logs tmp/462-tsc.log, tmp/462-lint.log, tmp/462-jest.log. No cli files changed, no Go gate needed. Read-only DB audit, no transport redesign.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
198 PostgREST request templates audited, zero remaining unsafe instances and none beyond the already-fixed export select. Reproduced the old 0/29470 failure and verified the current full export at 1976463/1976463. Added composed-request invariant coverage and author guidance, all app gates passed.
<!-- SECTION:FINAL_SUMMARY:END -->
