---
id: STATBUS-150
title: >-
  pg-regress-red: seed-guard trip (PGDATABASE vs statbus_seed) + db-init failure
  surfaced by ON_ERROR_STOP — red since 14:43
status: In Progress
assignee:
  - mechanic
created_date: '2026-07-08 23:17'
labels:
  - ci
  - testing
  - investigation
dependencies: []
references:
  - cli/
  - .github/workflows/pg_regress.yaml
  - postgres/init-db.sh
  - dev.sh
priority: high
ordinal: 151000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the pg_regress + Fast Tests pipelines are green again and every commit gets real SQL-test signal; no failure mode is dismissed as flaky.
> STAGE: mechanic diagnosing (read-only); fix shapes go to the architect before any code moves.

TIMELINE (foreman's pulls, 2026-07-08/09):
- Last green: run 28951341553 on c53bad203 at 14:41. The SAME commit failed at 14:43 (run 28951481521) — environment/path-dependent, not the commit.
- MODE 1 (14:43 → at least 21:32, runs 28951481521 / 28977128949): after "Acquired exclusive seed lock; running: [env STATBUS_SEED_LOCK_HELD=1 ./dev.sh recreate-seed]" → "Error: PGDATABASE=statbus_test is set but this command targets statbus_seed; unset PGDATABASE, or select a database with --target". Our own fail-fast guard tripping inside the CI seed-recreate path; only runs that take the recreate path hit it, explaining same-SHA pass/fail.
- MODE 2 (22:24, run 28979959082): SSH dial timeout to 162.55.61.141:22 — likely transient, noted only.
- MODE 3 (23:09, run 28982022243 on 08a3c9471): fresh volume, image rebuilt, "Container statbus-test-db Error … container statbus-test-db is unhealthy" ~5s after start. First seen with 129's ON_ERROR_STOP (752e5b4f1) in the built db image — prime suspect: 129 doing its job, surfacing a genuinely failing init-db statement on a fresh cluster; the statement needs naming from the container logs.

IMPACT: all SQL-test signal masked since 14:43; tonight's commits are Go/shell/docs so Go Test green covers them, but this must be green before the next migration-bearing change ships.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Mode 1 call chain named (guard site file:line, workflow env source, staleness rule that selects the recreate path) and the ruled fix shipped
- [ ] #2 Mode 3 failing init-db statement named verbatim from the test server's container logs and the ruled fix shipped (or 129 rolled back only if the architect rules the surfaced statement legitimate-by-design)
- [ ] #3 Oracle: two consecutive green pg_regress + Fast Tests runs on master, one of which takes the recreate-seed path
<!-- AC:END -->
