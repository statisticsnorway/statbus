---
id: STATBUS-162
title: >-
  pg-regress-db-log-artifact: archive the db container's logs on failure so
  init-db aborts are readable after the fact
status: To Do
assignee: []
created_date: '2026-07-12 03:39'
labels:
  - ci
  - testing
  - tooling
dependencies: []
references:
  - STATBUS-151
  - STATBUS-155
priority: low
ordinal: 163000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every red pg_regress run is self-sufficient evidence — the db container's own output (including init-db's [N/8] section markers) survives the run, without needing a kept environment.
> STAGE: CI diagnosability. FOUND: 2026-07-12 — the STATBUS-151 investigation could not read which init-db section aborted in four failing runs because the markers print to the db container's stderr, the Actions log carries only compose lifecycle, the containers were ephemeral, and no artifact was archived; one upload step would have decided that investigation in minutes (the adjudication's words).
> COMPLEXITY: mechanic-simple.

THE SHAPE (architect, 2026-07-12): on failure, the pg_regress workflow uploads the db container's logs (docker compose logs db) as a workflow artifact, modest retention. Composes with the STATBUS-155 principle: every red run self-sufficient, no hand-tracing from destroyed environments.

Origin: STATBUS-151 final adjudication, evidence-gap finding.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A failing pg_regress run's artifacts include the db container's logs (init-db markers readable)
- [ ] #2 Green runs upload nothing extra (failure-only, modest retention)
<!-- AC:END -->
