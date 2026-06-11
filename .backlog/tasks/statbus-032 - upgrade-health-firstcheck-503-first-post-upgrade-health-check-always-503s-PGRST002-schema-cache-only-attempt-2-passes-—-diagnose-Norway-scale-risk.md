---
id: STATBUS-032
title: >-
  upgrade-health-firstcheck-503: first post-upgrade health check always 503s
  (PGRST002 schema cache), only attempt 2 passes — diagnose + Norway-scale risk
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-06-11 15:45'
labels:
  - upgrade
  - health-check
  - postgrest
dependencies: []
priority: medium
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the King's dev upgrade to v2026.06.0-rc.01 (15:41:06): the FIRST post-upgrade health check always fails `503 PGRST002` ("Could not query the database for the schema cache. Retrying.", url .../rpc/auth_status); attempt 2 (5s later) passes 200. King flagged it: "something is up; investigate why; only the secondary passes."

LIKELY: PostgREST hasn't finished loading its schema cache when the upgrade's health-check loop fires attempt 1; the 5s retry catches it once warm. Benign at dev scale (self-heals), but worth fixing — AND there's a NORWAY-SCALE risk: PostgREST's schema-cache load scales with SCHEMA size (tables/functions/views), so on Norway's larger schema the cache load could need >1 retry, possibly exhausting the 5-attempt × 5s ≈ 25s budget → fail the upgrade's health verification → rollback (which currently hits the STATBUS-031 wedge). So this bears on Norway-readiness, not just cosmetics.

INVESTIGATE: where the health-check loop lives (cli/internal/upgrade, "Verifying health" / health-check-attempt), why attempt-1 always 503s relative to "Starting services" (docker compose up of the rest/PostgREST container), whether attempt-1 can pass cleanly (wait for PostgREST readiness / treat PGRST002 as not-ready-retry-WITHOUT-counting it / gate on the rest container's compose healthcheck), and the Norway-schema-scale risk. DIAGNOSE + PROPOSE; do not implement yet (upgrade code — foreman/King review the fix first).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Root cause of the attempt-1 503 identified — the race between the health-check firing and PostgREST's schema-cache load (file:line)
- [ ] #2 Norway-schema-scale risk assessed: can the cache load exceed the 5-attempt retry budget on a large schema and fail the upgrade's health verification?
- [ ] #3 A proposed fix so attempt-1 passes cleanly (or PGRST002 is handled as not-ready without burning a retry), for foreman/King review before implementation
<!-- AC:END -->
