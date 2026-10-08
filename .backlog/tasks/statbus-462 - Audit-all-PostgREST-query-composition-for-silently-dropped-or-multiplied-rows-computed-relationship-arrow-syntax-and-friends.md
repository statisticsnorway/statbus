---
id: STATBUS-462
title: >-
  Audit all PostgREST query composition for silently dropped or multiplied rows
  (computed-relationship arrow syntax and friends)
status: To Do
assignee: []
created_date: '2026-10-08 11:34'
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
- [ ] #1 An inventory exists of every PostgREST query in app/src with, for each, a verdict on whether it can silently drop or multiply rows, with file and line references and the construct named.
- [ ] #2 Every live instance that can lose rows is fixed, with a test that would have caught it.
- [ ] #3 A regression check asserts that the composed export select does not use a computed-relationship arrow projection, framed as an invariant on the query we send rather than a grep for a token.
- [ ] #4 The distinction between arrow syntax on a computed relationship and spread syntax for a to-one relationship is documented where query authors will see it.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The inventory states explicitly whether any hit beyond the export select exists today, so the scope of the class of bug is known rather than assumed.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner decision 2026-10-08 after the STATBUS-421 root cause: someone other than the export author should check whether this bites other places, as its own backlog item. The CSV column-order consequence of the Phase 1 fix needs no action, because the design is being replaced by the COPY route where column order is explicit.
<!-- SECTION:NOTES:END -->
