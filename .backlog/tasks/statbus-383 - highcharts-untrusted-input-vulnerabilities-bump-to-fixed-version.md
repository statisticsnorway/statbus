---
id: STATBUS-383
title: Bump Highcharts past the Q3/2026 untrusted-input vulnerability fixes
status: To Do
assignee: []
created_date: '2026-09-22 19:26'
updated_date: '2026-09-23 15:10'
labels:
  - security
  - dependencies
  - app
dependencies: []
references: []
priority: high
type: task
ordinal: 25
---

## Context

Highsoft advisory (forwarded by Erik Søberg, 2026-09-21; original
news@mail.highcharts.com 2026-09-18): "Fixed versions available:
Vulnerabilities in handling untrusted input in Highcharts products"
(UPDATES Q3/2026). Erik: consider taking the latest version into the
next build.

## Facts

- `app/package.json` pins `"highcharts": "^12.6.2"`; installed 12.6.2 before this task's upgrade.
- Highsoft's fixed-version table states that Highcharts Core, Stock, Maps, and Gantt are affected in all versions up to and including 13.0.2, and fixed in 13.1.0. The previously applied 12.6.2 bump was **not sufficient**.
- STATBUS uses the Core `highcharts` package only. It does not use Highcharts Dashboards or Grid Lite/Pro, so their separate fixed versions are not applicable.
- Highcharts Core 13.1.1 is publicly available (2026-09-20) and is the selected fixed version.

## Done when

- highcharts bumped to the advisory's fixed version (or a later 12.x),
  `pnpm install` + `pnpm run test` + build green.
- Advisory's fixed versions recorded in this file.
- Shipped in the next release after v2026.09.1 (or folded into the
  release train if it lands before stable is cut).

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: Highcharts bump is present only as uncommitted app/package.json and pnpm-lock.yaml work, with validation/release still outstanding.

Remaining: Commit the fixed Highcharts version, run frozen install, typecheck/lint/build/tests and the relevant chart smoke, then ship next release.
