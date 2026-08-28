---
id: STATBUS-274
title: >-
  test-isolation-prefix: isolation is keyed to the 4xx/5xx filename prefix,
  which also excludes a test from fast — the either/or is invisible until hit
status: In Progress
assignee:
  - '@architect'
created_date: '2026-08-27 13:51'
updated_date: '2026-08-28 10:16'
labels:
  - testing
dependencies: []
priority: low
type: enhancement
ordinal: 267000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Filed from the 265 gate-test review (architect, 2026-08-27). A pg_regress test gets database-per-test isolation ONLY via its numeric filename prefix (4xx/5xx, dev.sh:1031) — and that same prefix excludes it from the fast tier. So "isolated AND fast" is impossible, and nothing says so: the 094 exemption test needed both, took fast, and mitigated the shared-database hazard by hand (proven cleanup with a fresh-session assertion). The next test needing both will hit the same invisible either/or.

Fix: decouple isolation from the numeric prefix (e.g. an explicit marker the runner reads), so tier and isolation are independent choices. Small change in dev.sh's runner; the 094 file can then opt into isolation without leaving the gate.

WHAT IS ACHIEVED: a test chooses speed tier and isolation independently, and the constraint that forced 094's hand-mitigation is gone.
<!-- SECTION:DESCRIPTION:END -->
