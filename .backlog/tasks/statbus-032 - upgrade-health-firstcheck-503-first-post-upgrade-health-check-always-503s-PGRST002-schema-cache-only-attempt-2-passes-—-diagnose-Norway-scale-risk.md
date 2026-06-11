---
id: STATBUS-032
title: >-
  upgrade-health-firstcheck-503: first post-upgrade health check always 503s
  (PGRST002 schema cache), only attempt 2 passes — diagnose + Norway-scale risk
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-06-11 15:45'
updated_date: '2026-06-11 15:59'
labels:
  - upgrade
  - health-check
  - postgrest
dependencies: []
documentation:
  - >-
    doc-009 -
    STATBUS-032-—-PostgREST-readiness-admin-ready-warmup-for-the-upgrade-health-check-design.md
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

FIX DIRECTION UPGRADED (King steer + foreman web-research, 2026-06-11): use PostgREST's PROPER readiness signal instead of retry-and-ignore. PostgREST's admin server exposes `/ready` → 200 only when the schema cache is loaded AND the DB pool is up, 503 otherwise (docs.postgrest.org/en/stable/references/admin_server.html). We do NOT enable the admin server today (no PGRST_ADMIN_SERVER_PORT in docker-compose.rest.yml). PROPER FIX: (1) enable the admin server on an INTERNAL-ONLY/loopback port (it also exposes config + schema_cache endpoints → never public); (2) the upgrade health-check polls /ready until 200 (clean 'waiting for schema cache' message + ~2-3min cap) BEFORE the RPC check. Kills the scary PGRST002 entirely AND makes the wait scale with actual schema-load time (removes the fixed-25s-budget Norway risk, robustly). Architect dispatched to design (admin-server enablement + security + health-check rewiring), folding into the 031 review pass; King ratifies before implementation. Supersedes the mechanic's simpler PGRST002-exempt approach (kept as a possible fallback).

DESIGN COMPLETE (architect, 2026-06-11) → doc-009, awaiting King ratification before implementation. Shape: (1) enable PostgREST's admin server internal-only — PGRST_ADMIN_SERVER_PORT=3001 in docker-compose.rest.yml + loopback host mapping ${REST_ADMIN_BIND_ADDRESS}:3001, new derived port = slot offset+6 (free in all modes, config.go:438-443), bind generated as 127.0.0.1:<port> exactly like REST_BIND_ADDRESS (config.go:499) — same security posture as the existing REST port (loopback + compose network only, nothing public). (2) waitForRestReady warmup at the TOP of healthCheck (exec.go:1292, its one caller service.go:4036 covers both dispatch paths): GET /ready every 2s until 200, refused/503 both = keep waiting, cap = new shared const RestReadyTimeout=5m (012 generous-budget doctrine; King may trim to 3m), progress.Write every ~15s feeds the 3-min gated ticker (watchdog.go:134) — the 031-class subtlety handled explicitly. Cap expiry → postSwapFailure with refused-vs-503-distinguished actionable messages. (3) Mechanic's PGRST002-exempt fallback: DROPPED — dead path after warmup; a silent fallback would mask a future admin-mapping regression (doc-006 vacuity lesson); self-consistency holds because config generate (step 7) + container recreate (step 11) precede the check in the same pipeline. Functional RPC probe unchanged after warmup. Kills the scary PGRST002 AND the fixed-25s Norway budget risk (cache-load wait now scales with reality). Proof: unit tests (httptest /ready sequences + structural warmup-precedes-probe guard), every harness post-swap scenario as regression net, dev-journal observation GREEN (zero PGRST002), rune canary journal as the scale measurement — a deterministic VM RED for the race is not honestly producible (stated in doc-009 §Verification). Ships with the 031 fix in the gate-maker batch (doc-007 critical path, no new step).
<!-- SECTION:NOTES:END -->
