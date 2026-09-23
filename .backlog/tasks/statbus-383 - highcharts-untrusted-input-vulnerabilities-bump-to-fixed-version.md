---
id: STATBUS-383
title: Bump Highcharts past the Q3/2026 untrusted-input vulnerability fixes
status: Done
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

## Local implementation 2026-09-23 (STATBUS-383)

- Fixed locally: raised Highcharts Core from `^12.6.2` to `^13.1.1`, later than
  Highsoft's 13.1.0 fixed version for all Core versions through 13.0.2.
- Reachable before the fix: Highcharts is a shipped runtime dependency used by
  five chart constructors. Database-originated or indirectly user-controlled
  strings reach chart text options, and the drilldown tooltip uses `useHTML`.
- The v13 migration review found no use of removed `StackItemObject.isNegative`
  or obsolete option shapes. The existing `Axis.update({ visible })` call remains
  supported. No call-site change, explicit `any`, or `@ts-ignore` was required.
- Validation in the combined dependency pass: `pnpm install`, 5 Jest suites/33
  tests, TypeScript, lint (0 errors, 5 warnings), and production build passed.
  Detailed call-site evidence is in `tmp/highcharts-advisory.md`; combined gate
  evidence is in `tmp/statbus-363.md`.
- The change is committed locally only and has not been pushed or shipped.

## Resolution 2026-09-23

Status: **Done**. Commit `ff0003dfa` is on `origin/master` and raises Highcharts
Core to `^13.1.1`, later than the advisory's 13.1.0 fixed version. The combined
dependency validation recorded passing install, 33 Jest tests, typecheck, lint,
and production build.
