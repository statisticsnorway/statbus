---
id: STATBUS-032
title: >-
  upgrade-health-readiness: poll PostgREST admin /ready before the RPC health
  check — kills the PGRST002 first-fail + the fixed-25s Norway budget
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-06-11 15:45'
updated_date: '2026-06-12 07:52'
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
PROBLEM (King-sighted on the rc.01 dev upgrade; mechanic-diagnosed): the post-upgrade health check fires immediately after `docker compose up -d` (applyPostSwap step 12, service.go:4034-4038) while PostgREST is still loading its schema cache → attempt 1 always fails 503 PGRST002 (scary defect-shaped journal line). Budget is FIXED at 5×5s=25s but cache load scales with SCHEMA complexity → on Norway's schema all attempts can burn → false health-fail → rollback (which today hits the 031 wedge). KING STEER: fix properly with PostgREST's real readiness signal, not retry-and-ignore.

THE FIX (designed; awaiting King ratification — AC#4):
1. Enable PostgREST's admin server INTERNAL-ONLY: PGRST_ADMIN_SERVER_PORT=3001 in docker-compose.rest.yml + host mapping ${REST_ADMIN_BIND_ADDRESS}:3001. New derived port = slot offset+6 (King-affirmed; verified free in every mode), generated as 127.0.0.1:<port> exactly like REST_BIND_ADDRESS (config.go:499). Loopback + compose network only — the admin server is unauthenticated (serves /config etc.), never public, no Caddy route. Image v12.2.8 supports it.
2. Warmup at the TOP of healthCheck (exec.go:1292; its only caller is service.go:4036, covering both service and inline dispatch): GET /ready every 2s until 200. 503 AND connection-refused both just keep waiting (one code path). Cap = new shared const RestReadyTimeout=5m (generous-budget doctrine from 012; trim to 3m if the King prefers). The loop emits a progress line every ~15s — this narrates the journal AND feeds the 3-min progress-gated watchdog ticker (watchdog.go:134) so the wait itself can't get the unit killed. On cap expiry → postSwapFailure with messages that distinguish refused-throughout ("admin server unreachable — run ./sb config generate"; config drift) from 503-throughout ("schema cache never loaded — check docker compose logs rest").
3. NO PGRST002 fallback path (the mechanic's interim option is dropped): after /ready=200 the cold-cache race cannot occur, and a silent fallback would mask a future loss of the readiness signal. The functional RPC probe (POST /rpc/auth_status, 5×5s) stays unchanged after the warmup.

PROOF (no deterministic VM RED is honestly possible for a cache-load race): unit tests (httptest /ready sequences: 503→200, refused→200, never-ready expiry messages; + a structural test that the warmup precedes the first RPC POST); every post-swap harness scenario exercises the warmup as a regression net; the next dev-slot upgrade journal must show the clean readiness wait and ZERO PGRST002; the rune canary journal gives the real Norway-scale cache-load measurement.

Also: add the offset+6 = rest-admin row to AGENTS.md's port table. Ships with the 031 fix in the gate-maker batch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Root cause of the attempt-1 503 identified — the race between the health-check firing and PostgREST's schema-cache load (file:line)
- [x] #2 Norway-schema-scale risk assessed: can the cache load exceed the 5-attempt retry budget on a large schema and fail the upgrade's health verification?
- [x] #3 A proposed fix so attempt-1 passes cleanly (or PGRST002 is handled as not-ready without burning a retry), for foreman/King review before implementation
- [ ] #4 King ratifies the fix design in this description (admin server internal-only at offset+6, /ready warmup in healthCheck, 5m cap, no fallback)
- [ ] #5 Admin server enabled internal-only: compose env + loopback port mapping + config-gen derived REST_ADMIN_BIND_ADDRESS; nothing publicly reachable
- [ ] #6 healthCheck polls /ready to 200 before the RPC probe; ~15s progress lines feed the watchdog gate; cap-expiry messages distinguish config-drift (refused) from cache-stuck (503)
- [ ] #7 Unit tests: 503→200 waits+proceeds, refused→200 tolerated, never-ready expiry with both messages, structural warmup-precedes-probe guard
- [ ] #8 Observed GREEN: next dev-slot upgrade journal shows the readiness wait and zero PGRST002; AGENTS.md port table carries the offset+6 row
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CONSOLIDATED STATE: mechanic diagnosed the root cause (no pre-wait after compose up; fixed 25s budget) and proposed a PGRST002-exempt retry loop; the King upgraded the direction to PostgREST's real /ready signal; architect designed it (description above = the work order; deep-reference doc-009 carries the alternatives analysis incl. why no-fallback and why port offset+6 — King-affirmed). Awaiting King ratification (AC#4), then implement in one commit with unit tests; ships in the gate-maker batch alongside 031.
<!-- SECTION:NOTES:END -->
