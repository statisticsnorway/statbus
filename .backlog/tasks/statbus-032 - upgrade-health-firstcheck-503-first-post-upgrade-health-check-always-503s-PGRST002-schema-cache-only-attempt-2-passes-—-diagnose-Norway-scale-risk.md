---
id: STATBUS-032
title: >-
  upgrade-health-readiness: poll PostgREST admin /ready before the RPC health
  check — kills the PGRST002 first-fail + the fixed-25s Norway budget
status: To Do
assignee:
  - '@mechanic'
created_date: '2026-06-11 15:45'
updated_date: '2026-06-15 12:07'
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
CONSOLIDATED STATE: mechanic diagnosed the root cause (no pre-wait after compose up; fixed 25s budget) and proposed a PGRST002-exempt retry loop; the King upgraded the direction to PostgREST's real /ready signal; architect designed it (description above = the work order). Awaiting King ratification (AC#4), then implement in one commit with unit tests; ships in the gate-maker batch alongside 031.

== DEEP REFERENCE (folded from doc-009 — the alternatives analysis behind the work order) ==

PORT CHOICE — why offset +6, challenged + verified: one new loopback host mapping is the structural minimum. The zero-new-port alternatives all fail: (a) docker-exec an in-container probe — the official PostgREST image is distroless, no shell/curl; (b) host→container-IP directly — works on Linux, breaks on macOS Docker Desktop (dev parity) and trades the static .env pattern for runtime docker inspect; (c) admin on a unix socket — PostgREST's admin server is port-only (only the MAIN server supports PGRST_SERVER_UNIX_SOCKET); (d) reuse the existing rest mapping — the admin server is a different container port, needs its own host mapping; (e) route /ready through Caddy — puts unauthenticated admin endpoints on the public surface. Verified +6..+9 unclaimed repo-wide (config.go is the sole port authority, assigns only +0..+5; standalone overrides only http/https/db, so +6 is uniform across modes). The scheme's convention is sequential assignment with exposure decided by MODE not index — +6 is exactly that. Add the +6=rest-admin row to AGENTS.md's port table.

SECURITY POSTURE: the admin endpoints (/ready,/live,/config,/schema_cache — unauthenticated in v12) become reachable only from (a) host loopback — same trust level as the main REST port today (and as docker inspect, which already exposes PGRST_JWT_SECRET) and (b) the compose network — where app/worker already hold same-or-higher-trust credentials. Nothing public: no Caddy route, no non-loopback bind.

WHY NO FALLBACK (the mechanic's interim PGRST002-detect-and-wait is dropped entirely): after /ready=200 the cold-cache race cannot occur, so it is dead defensive code future readers would mistake for a needed path; and a silent fallback when /ready is unreachable would MASK exactly the regression class doc-006 taught us to fear (a future compose refactor drops the admin mapping → fallback engages → nobody notices the readiness signal is gone → vacuous green). Unreachable-after-config-generate is config corruption → fail fast with the actionable message. Safe because the polling binary ships in the SAME commit as the compose+config change, and applyPostSwap regenerates config (step 7) + recreates the rest container (step 11) before step 12 runs.

WATCHDOG INTERACTION (the 031-class subtlety): step 12 runs under applyPostSwap's progress-GATED ticker (armed service.go:3785-3792; gate closes after applyPostSwapStallThreshold=3min of silence, watchdog.go:134). A silent 4-min warmup would close the gate → SIGABRT. The loop therefore emits progress.Write every ~15s — each Write pings the watchdog (emitHeartbeat) and bumps the gate. Doctrine-consistent: the loop genuinely advances (polling), output is its liveness signal, bounded by its own 5-min timeout.

OUT OF SCOPE (named, not forgotten): container-level compose healthcheck: stanza (orthogonal — the Go poll narrates the journal + feeds the watchdog; a compose healthcheck does neither; + needs an in-image probe the distroless image lacks); rollback's post-restore verification (031's domain — rollback comes up at the OLD version); /live,/config,/schema_cache (enabled as a side effect, nothing consumes them).

VERIFICATION (honest — no deterministic VM RED for a cache-load race): unit tests are the real teeth (httptest /ready: 503×N→200, refused→503→200, never-200 expiry with the refused-vs-503 message distinction, + structural warmup-precedes-probe guard); config tests (+6 port + .env line); every post-swap harness scenario exercises the warmup as a free regression net; observed GREEN = next dev-slot upgrade journal shows the readiness wait + zero PGRST002; scale-proof = the rune-no canary journal (real Norway schema cache-load duration).

== ARCHITECT DESIGN: container-level compose healthcheck (King-requested, 2026-06-15) — design-only, no code ==

The King asked us to seriously design the compose `healthcheck:` approach (currently OUT OF SCOPE) and answer: “would a container-level healthcheck mean the container FAILS LIVENESS unless Postgres is up? maybe that is correct.” Answered below against verified facts.

VERIFIED FACTS (web + codebase):
- PostgREST admin endpoints (docs, v12): `/live` = 200 if the PROCESS is running (500 otherwise) — does NOT need the DB. `/ready` = 200 only if BOTH the connection pool AND schema cache are good, else 503 — NEEDS Postgres up + cache loaded. (This is the live/ready split the King’s question turns on.)
- The pinned image is `postgrest/postgrest:v12.2.8`, UPSTREAM, distroless (docker-compose.rest.yml:5). No shell → no CMD-SHELL; no curl/wget → no HTTP client for a CMD exec-form probe. No rest Dockerfile in the repo (can’t bake a probe without introducing one).
- A `postgrest --ready` self-probe flag exists ONLY in `devel` (PR #4269, Sep 2025) — NOT in stable v12.2.x. So `["CMD","postgrest","--ready"]` is unavailable on our pinned version.
- ALREADY PRESENT: `db` has a `pg_isready` healthcheck (postgres/docker-compose.yml:13-17) and rest/app/worker `depends_on: db: condition: service_healthy` (docker-compose.rest.yml:8). So the foundational “don’t start until Postgres accepts connections” ordering is DONE. `--wait` is used nowhere; no /ready//live/admin references exist yet (the 032 Go-poll is novel).

(1) HOW to implement on the distroless image — the constraint is the story:
- pg_isready (db) checks Postgres, NOT PostgREST schema-cache readiness — can’t stand in for a rest /ready probe.
- On v12.2.8 there is NO in-image probe. Real options: (a) CUSTOM rest image — `FROM postgrest/postgrest:v12.2.8` + COPY a tiny static HTTP-probe binary, then `healthcheck: ["CMD","/probe","http://127.0.0.1:<admin>/ready"]`. Cost: a new Dockerfile + build step + a vetted probe binary (supply chain) + divergence from the clean upstream pin the repo deliberately keeps. (b) Sidecar — a compose healthcheck is per-container and can’t set ANOTHER container’s health; a sidecar only self-gates, awkward, rejected. (c) FORWARD PATH — bump PostgREST to a release carrying #4269, then the healthcheck is a clean 3-line exec-form stanza `["CMD","postgrest","--ready"]` (no shell, no extra binary, no custom image). Recommended over (a).

(2) LIVENESS behavior — the King’s direct question, answered: a `/ready` compose healthcheck reports the container UNHEALTHY whenever the schema cache isn’t loaded OR Postgres is down. So YES — with /ready, the container “fails health” unless Postgres is up + cache loaded. What compose DOES with that:
- Plain `docker compose` does NOT restart an unhealthy container. `restart: unless-stopped` (which rest has) fires on container EXIT, not on health status. Only Swarm reschedules on unhealthy. So an unhealthy rest just shows `(unhealthy)` in `docker ps` — it is NOT killed/restarted today.
- `depends_on: condition: service_healthy` gates DEPENDENTS from STARTING until the target is healthy. Today app/worker/rest gate on `db` only. Adding a rest healthcheck + making app/worker depend on `rest: service_healthy` would delay their start until rest is /ready (full cache load) — on Norway-scale that is the very slowness 032 manages; weigh before adopting.
- `docker compose up -d --wait` blocks until healthchecked services are healthy. NOT used anywhere. If the upgrade’s `up` added --wait against /ready, the `up` itself would block through the cache load (could stall/slow it) and lacks the actionable refused-vs-503 messaging the Go-poll gives.
LIVENESS vs READINESS — the crux: Docker’s single `healthcheck:` CONFLATES them (unlike k8s’ separate probes). `/ready` is a READINESS signal (can it serve?), NOT liveness (should it be killed?). Using /ready as health is right for READINESS GATING but WRONG as a restart trigger — you must not kill/restart rest just because Postgres blips (a restart won’t fix the DB and the cache reload would re-fail → loop). The hazard is LATENT today (plain compose doesn’t act on unhealthy) but becomes real if Swarm / an autoheal watcher / `--wait` is ever added. So a rest healthcheck should be understood as READINESS; for any LIVENESS purpose the correct probe is `/live` (process-up, DB-independent). The db `pg_isready` healthcheck (already present) is the foundational ordering gate and is correct as-is (checks Postgres-accepting-connections, not PostgREST cache).

(3) RELATION to 032’s Go-poll /ready warmup — reconciled honestly: GENUINELY COMPLEMENTARY, different layers, NOT substitutes.
- Go-poll = UPGRADE-FLOW readiness: runs only in the post-swap healthCheck; value = narrating the upgrade journal (~15s lines), FEEDING the upgrade’s progress-gated watchdog, the actionable refused(config-drift)-vs-503(cache-stuck) failure messages, and gating the functional RPC probe. A compose healthcheck does NONE of these → 032’s original out-of-scope reasoning HOLDS on this axis.
- Compose healthcheck = STEADY-STATE orchestration readiness: all the time (not just upgrades); value = `docker ps` health visibility + depends_on gating for normal boot/restart. The Go-poll does NONE of this (upgrade-flow only).
The King’s instinct does NOT overturn the out-of-scope call — it ADDS an orthogonal value the Go-poll never claimed. Neither replaces the other.
OUT-OF-SCOPE NOTE UPDATED (supersedes the description’s line): not “orthogonal, skip” but “COMPLEMENTARY at a different layer; defer on cost” — a compose /ready healthcheck adds steady-state orchestration readiness the Go-poll doesn’t provide, but is BLOCKED today by the distroless-no-probe constraint on v12.2.8 (custom image required) and cannot replace the Go-poll. Revisit when PostgREST gains `--ready` (#4269, post-v12.2.8) — then ~free.

(4) RECOMMENDATION — DO IT AS A COMPLEMENT, but DEFER the rest healthcheck to the postgrest bump; do NOT build a custom image now:
- KEEP the db `pg_isready` healthcheck + depends_on (already shipped — highest-value foundational piece; rest/app/worker already wait for Postgres).
- SHIP 032’s Go-poll as designed (ratify AC#4) — the upgrade-flow readiness, independent of any compose healthcheck.
- REST compose healthcheck: DEFER to the next PostgREST bump carrying #4269 → then a clean exec-form `healthcheck: ["CMD","postgrest","--ready"]` (no custom image). When added: treat as READINESS; use `/live` for any liveness need; do NOT wire as a restart trigger; only add app/worker `depends_on: rest: service_healthy` if steady-state ordering is worth delaying their boot through cache load.
- Do NOT add `--wait` to the upgrade’s `up` as a readiness mechanism — the Go-poll covers upgrade-flow readiness better (journal+watchdog+diagnostics).
TRADEOFFS: custom image NOW → +steady-state `docker ps` readiness today; −new Dockerfile/build/maintenance + upstream-pin divergence + a probe binary to vet. Defer to the bump → +zero cost, clean upstream `--ready`; −no steady-state rest readiness until then. The two highest-value cases (startup ordering + upgrade-flow readiness) are ALREADY covered (existing db healthcheck + 032 Go-poll); the rest compose healthcheck is lowest marginal value AND most expensive today — hence defer.
DIRECT ANSWER to the King: yes, a /ready healthcheck reports unhealthy unless Postgres is up — CORRECT for readiness (gate traffic/dependents), INCORRECT for liveness (don’t kill rest over a DB blip); compose collapses both into one status, so if a restart-on-unhealthy mechanism is ever added a /ready healthcheck would cause harmful restart loops (use /live for liveness). Given the foundational gate already exists and the clean `--ready` path is one postgrest bump away, the principled move is defer-not-custom-image.

STATUS CORRECTED 2026-06-15 (King caught it): In Progress → To Do, assignee cleared. NOBODY is actively working this — it has been BLOCKED on King ratification (AC#4) since 2026-06-12. Design is COMPLETE (AC#1-3 done + the compose-healthcheck analysis added 06-15). Implementation (AC#5-8) cannot start until the King ratifies the design (admin server internal-only at offset+6; /ready warmup in healthCheck; 5m cap; no PGRST002 fallback). 'In Progress' was inaccurate — it implied active work when the task is parked awaiting a decision. When the King ratifies, assign + move to In Progress for the implementation commit.
<!-- SECTION:NOTES:END -->
