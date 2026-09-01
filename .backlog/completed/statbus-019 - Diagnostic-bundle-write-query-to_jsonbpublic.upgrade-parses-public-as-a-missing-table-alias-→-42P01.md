---
id: STATBUS-019
title: >-
  Diagnostic-bundle write query: to_jsonb(public.upgrade) parses 'public' as a
  missing table alias → 42P01
status: Done
assignee: []
created_date: '2026-06-09 01:36'
updated_date: '2026-06-11 07:49'
labels:
  - install-recovery
  - product
  - diagnostics
  - low-priority
dependencies: []
references:
  - cli/internal/upgrade/bundle.go
priority: medium
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
UPGRADED from LOW → MEDIUM + LOCATED (2026-06-10, comprehensive run 27242482272). This is NOT diagnostic-only/cosmetic as first thought — it FAILS ≥3 install-recovery scenarios outright (3-postswap-between-migrations-kill, 3-postswap-mid-migration-kill [a REGRESSION — was GREEN], 4-rollback-kill) with `ERROR: missing FROM-clause entry for table "public"` (42P01). LOCATION: cli/internal/upgrade/bundle.go:100 — `SELECT to_jsonb(public.upgrade)::text FROM public.upgrade WHERE id = $1`. The FROM clause aliases the table as `upgrade` (implicit alias = table name), so `to_jsonb(public.upgrade)` references a non-existent table `public` → 42P01. FIX (clean, ~1 line): alias the table — `SELECT to_jsonb(u)::text FROM public.upgrade u WHERE id = $1` (or `to_jsonb(upgrade)`). NOT the 017 fix (017 = service.go+install_upgrade.go, zero SQL; this is the diagnostic-bundle write on the upgrade-completion path — the GREEN reproducers passed through the rollback path which doesn't call it). Architect confirming the exact reach-mechanism + that 017 is clean; then engineer applies the 1-line fix → re-run the 3 scenarios.

CORRECTION (architect deep-trace, 2026-06-10) — my prior 'FAILS ≥3 scenarios' note was WRONG (I propagated an operator misattribution). The 42P01 is NON-FATAL and fails ZERO scenarios: bundle.go:101-103 catches it → narrate('Warning: bundle write skipped …') + return void (writeDiagnosticBundle is best-effort). Proof: the identical warning appears in PASSING scenarios (3-postswap-archivebackup-resume line 41866) and in the 2 GREEN wedge reproducers — a passing scenario emitting it = definitionally non-fatal. So it's a co-occurring red herring in the comprehensive-run failures, not their cause.
BUT it is NOT cosmetic: the forensic *.bundle.txt is SILENTLY SKIPPED on EVERY rollback (production + test) → we lose support diagnostics exactly when a rollback happens and they're most needed. That's the real (diagnostic-quality) reason it's worth MEDIUM. One-line fix stands: `SELECT to_jsonb(u)::text FROM public.upgrade u WHERE u.id=$1` (bundle.go:100). Does NOT gate STATBUS-017. NOT touched by the 017 fix (zero SQL there).

FIX APPLIED (engineer, 2026-06-10, working tree — foreman sole committer). cli/internal/upgrade/bundle.go:100 → SELECT to_jsonb(u)::text FROM public.upgrade u WHERE u.id = $1. make -C cli build clean. No Go test pins the SQL string. The forensic *.bundle.txt now writes on the rollback path instead of being silently skipped (42P01). Awaiting foreman review+commit.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Committed 751bae42c on master. bundle.go:100 query aliased: `SELECT to_jsonb(u)::text FROM public.upgrade u WHERE u.id=$1` (was to_jsonb(public.upgrade), which 42P01'd). Architect-reviewed PASS — confirmed the only to_jsonb table-ref site in cli/ (no sibling). Validated by comprehensive run 27306718138 (no 019-related failure). Restores the forensic diagnostic bundle on every rollback.
<!-- SECTION:FINAL_SUMMARY:END -->
