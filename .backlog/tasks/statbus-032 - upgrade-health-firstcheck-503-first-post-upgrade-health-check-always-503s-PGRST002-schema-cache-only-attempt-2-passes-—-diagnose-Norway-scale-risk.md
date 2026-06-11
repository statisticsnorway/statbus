---
id: STATBUS-032
title: >-
  upgrade-health-firstcheck-503: first post-upgrade health check always 503s
  (PGRST002 schema cache), only attempt 2 passes — diagnose + Norway-scale risk
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-06-11 15:45'
updated_date: '2026-06-11 15:50'
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
- [x] #1 Root cause of the attempt-1 503 identified — the race between the health-check firing and PostgREST's schema-cache load (file:line)
- [x] #2 Norway-schema-scale risk assessed: can the cache load exceed the 5-attempt retry budget on a large schema and fail the upgrade's health verification?
- [x] #3 A proposed fix so attempt-1 passes cleanly (or PGRST002 is handled as not-ready without burning a retry), for foreman/King review before implementation
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DIAGNOSIS COMPLETE (mechanic, 2026-06-11). ROOT CAUSE: service.go:4035-4036 calls healthCheck(5, 5s) immediately after `docker compose up -d` returns (:4012) with NO pre-wait (the comment at :4023-4026 even notes up-d != healthy); exec.go:1308-1328 fires attempt-1 with no initial sleep. PostgREST needs ~5s after container start to connect + load its schema cache → PGRST002 503 in that window. There is NO healthcheck stanza on the `rest` container (docker-compose.rest.yml has only depends_on: db: service_healthy) → compose has no rest-readiness signal AND the Go loop doesn't wait. Consistent: attempt-1 fails, attempt-2 (5s later) passes.

NORWAY-SCALE RISK = REAL (AC#2 confirmed): PostgREST cache load scales with SCHEMA complexity, not data. Budget = 5 attempts x 5s = 25s. Dev loads ~5s (1 failed attempt). On Norway's larger schema, if cache load >25s -> ALL 5 attempts return PGRST002 -> healthCheck errors -> postSwapFailure -> rollback -> hits the STATBUS-031 restore wedge. So 032 is a Norway-readiness item, NOT cosmetic.

FIX (proposed, AC#3): treat PGRST002 as a startup-warmup signal -> don't count it against the 5-retry budget. Mechanic rec = Option A: a separate warmup pre-loop (cap ~24x5s=120s, retries only on PGRST002, breaks out on anything else), so the 5-attempt budget only fires against genuine health failures. exec.go:healthCheck only; no docker-compose change needed.

REMAINING: King ratify the warmup-exempt approach -> implement (small) -> ship before the rune-no canary. Fold into the 031 review pass.
<!-- SECTION:NOTES:END -->
