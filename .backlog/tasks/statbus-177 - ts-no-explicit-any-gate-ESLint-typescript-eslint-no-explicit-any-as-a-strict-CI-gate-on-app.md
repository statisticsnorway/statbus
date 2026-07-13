---
id: STATBUS-177
title: >-
  ts-no-explicit-any-gate: ESLint @typescript-eslint/no-explicit-any as a strict
  CI gate on app/
status: To Do
assignee: []
created_date: '2026-07-13 14:45'
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
