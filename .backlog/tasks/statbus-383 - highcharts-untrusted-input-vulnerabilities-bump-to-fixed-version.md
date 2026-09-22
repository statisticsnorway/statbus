---
id: STATBUS-383
title: Bump Highcharts past the Q3/2026 untrusted-input vulnerability fixes
status: To Do
assignee: []
created_date: '2026-09-22 19:26'
updated_date: '2026-09-22 19:26'
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

- `app/package.json` pins `"highcharts": "^12.5.0"`; installed 12.5.0.
- Highcharts renders statistical-unit names and other DB-originated
  strings; the exposure surface is whatever the Q3/2026 advisory covers
  (exact CVEs and fixed version numbers still to be pinned from the
  advisory/changelog).

## Done when

- highcharts bumped to the advisory's fixed version (or a later 12.x),
  `pnpm install` + `pnpm run test` + build green.
- Advisory's fixed versions recorded in this file.
- Shipped in the next release after v2026.09.1 (or folded into the
  release train if it lands before stable is cut).
