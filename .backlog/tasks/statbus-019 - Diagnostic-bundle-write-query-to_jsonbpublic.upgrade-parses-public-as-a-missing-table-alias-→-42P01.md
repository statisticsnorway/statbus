---
id: STATBUS-019
title: >-
  Diagnostic-bundle write query: to_jsonb(public.upgrade) parses 'public' as a
  missing table alias → 42P01
status: To Do
assignee: []
created_date: '2026-06-09 01:36'
labels:
  - install-recovery
  - product
  - diagnostics
  - low-priority
dependencies: []
references:
  - cli/internal/upgrade/bundle.go
priority: low
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND overnight 2026-06-09 (engineer, run 27168472969 / 5-install-drifted-unit-reconciled). PRODUCT bug, but DIAGNOSTIC-ONLY (does NOT break recovery) → low priority.

SYMPTOM: "Warning: bundle write skipped — could not read upgrade row id=11: ERROR: missing FROM-clause entry for table \"public\" (SQLSTATE 42P01)".

ROOT CAUSE: the diagnostic-bundle writer runs `SELECT to_jsonb(public.upgrade)::text FROM public.upgrade WHERE id=$1` (cli/internal/upgrade/bundle.go ~:100). Inside `to_jsonb(...)`, Postgres parses `public.upgrade` as table-alias.column (alias `public`), but the FROM clause aliases the table as `upgrade` (the bare table name), so alias `public` is not in scope → 42P01.

FIX: `to_jsonb(upgrade)` — reference the table by its FROM alias (the unqualified name). Or alias explicitly: `FROM public.upgrade u … to_jsonb(u)`.

IMPACT: the upgrade-service diagnostic bundle (support artifact) is silently skipped on write. Recovery is unaffected (it's a diagnostic). Low-priority King item; the fix is a one-line product change (King-gated, not done autonomously).
<!-- SECTION:DESCRIPTION:END -->
