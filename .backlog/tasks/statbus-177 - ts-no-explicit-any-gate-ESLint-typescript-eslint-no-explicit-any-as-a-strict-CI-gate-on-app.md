---
id: STATBUS-177
title: >-
  ts-no-explicit-any-gate: ESLint @typescript-eslint/no-explicit-any as a strict
  CI gate on app/
status: To Do
assignee: []
created_date: '2026-07-13 14:45'
updated_date: '2026-07-14 17:45'
labels:
  - ci
  - quality-gate
  - typescript
dependencies: []
priority: medium
ordinal: 178000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King-approved quality gate. Enforce @typescript-eslint/no-explicit-any as an error in app/ ESLint config, gated in CI (the existing app_build_and_lint workflow) so new `any` cannot land.

Shape (per the ratified strict-gating doctrine): strict job failure, no continue-on-error. Bypass, if ever needed, is a loud explicit toggle.

Rollout: the existing codebase has `any` usages; burn them down to zero (typed replacements, discriminated unions per the reach-for-types principle) or, where a boundary genuinely requires it, an explicit per-line eslint-disable with a justification comment. The rule must land as error (not warn) on green master.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 @typescript-eslint/no-explicit-any set to error in app/ ESLint config
- [ ] #2 CI lint job fails on violations — no continue-on-error, no warn-level soft landing
- [ ] #3 Existing any usages resolved with real types or per-line justified disables
- [ ] #4 Gate lands green on master
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-14 17:45
---
SCOPE FINDING + INVENTORY (2026-07-14): the app has NO ESLINT AT ALL — verified directly in app/package.json: no lint script, zero eslint dependencies, no config file. AGENTS.md's documented `pnpm run lint` is STALE documentation (the doc fix rides this ticket). So this ticket's real scope is: (1) INTRODUCE ESLint to the app (eslint + typescript-eslint + eslint-config-next per Next.js 15 convention, flat config), (2) set no-explicit-any to error, (3) burn down, (4) wire the CI gate (check what app_build_and_lint-workflow.yaml actually runs today — presumably build+prettier only — and add the lint job strictly). ROUGH INVENTORY (tester, grep-based proxy since eslint can't run yet — pattern `: any`, misses `as any`/`any[]`/generics): 94 hits. Concentration: atoms/ 16, lib/ 10, legal-units/[id] 10, import/jobs/[jobSlug]/data 10 (one file alone has 10), jotai-state-management-reference 7 (a REFERENCE page — candidate for per-line justified disables rather than typing). Log: tmp/any-inventory-177.log. The true count lands only after ESLint is introduced (rule-based, not grep).
---
<!-- COMMENTS:END -->
