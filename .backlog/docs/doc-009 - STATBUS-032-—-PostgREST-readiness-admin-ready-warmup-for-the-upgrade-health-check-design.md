---
id: doc-009
title: >-
  STATBUS-032 — PostgREST readiness: admin /ready warmup for the upgrade
  health-check (design)
type: specification
created_date: '2026-06-11 15:59'
tags:
  - install-recovery
  - upgrade
  - health-check
  - postgrest
  - architect-plan
  - needs-king-ratification
---
# STATBUS-032 — PostgREST readiness: admin `/ready` warmup for the upgrade health-check

**Architect (Fable), 2026-06-11. DESIGN ONLY — King ratifies before implementation (upgrade-pipeline + config). Reviewed together with the 031 design (doc-007 Track A1): both close failure modes on the same Norway-critical chain — 032 prevents a false health-fail from *entering* rollback; 031 makes rollback itself survivable.**

## Context — what fails and why it matters

Every post-upgrade health verification fires immediately after `docker compose up -d` returns (applyPostSwap step 11, service.go:4012 → step 12, :4034-4038) with no readiness wait — the step-11 comment itself concedes "up -d returned ok … NOT that health checks have passed" (:4023-4026). PostgREST then needs seconds-to-? to connect and load its schema cache; until it does, the functional probe (`POST /rpc/auth_status`, exec.go:1311) returns **503 PGRST002** — a scary, defect-shaped line in every upgrade journal (the King saw it on the rc.01 dev upgrade; attempt 2 passes).

**The Norway-scale risk (mechanic-confirmed, 032 AC#2):** the budget is fixed — 5 attempts × 5 s = 25 s (service.go:4036) — but schema-cache load scales with *schema complexity*. If Norway's schema needs >25 s, all 5 attempts burn on PGRST002 → `healthCheck` errors → `postSwapFailure` → rollback → today that rollback hits the 031 restore wedge. A fixed budget on scaled work is the exact mistake 012 taught us to remove (5 m → 30 m migrate budget). This is a Norway-readiness item, not cosmetics.

**The proper signal exists and we don't use it:** PostgREST's admin server (enabled by `PGRST_ADMIN_SERVER_PORT`) exposes `GET /ready` → **200 only when the schema cache is loaded AND the DB pool is up**, 503 otherwise (`/live` = process up). Our image is `postgrest/postgrest:v12.2.8` (docker-compose.rest.yml:5) — admin server fully supported. Today no `PGRST_ADMIN_SERVER_PORT` is set anywhere.

## Design

### 1. Enable the admin server, internal-only (compose + config generation)

The admin server is unauthenticated and (in v12) also serves `/config` and `/schema_cache` introspection — it must never be publicly reachable. The codebase already has the exact pattern to copy: the main REST port is bound **loopback-only by construction** — `PostgrestBindAddress = "127.0.0.1:<port>"` (cli/internal/config/config.go:499), compose maps `"${REST_BIND_ADDRESS}:3000"` (docker-compose.rest.yml:35), and Caddy routes nothing to it. The admin port mirrors this exactly:

- **Port scheme:** slot offsets +0..+5 are assigned (config.go:438-443); **+6 is free in every mode** (the standalone branch overrides only http/https/db ports, :452-460 — app/rest stay slot-based, so +6 is uniform). Admin port = `portOffset + 6` (slot 1 → 3016, slot 2 → 3026, …).
- **config.go:** new derived pair `RestAdminPort = portOffset + 6` / `RestAdminBindAddress = "127.0.0.1:<port>"` (beside :441/:499); new `.env` template line `REST_ADMIN_BIND_ADDRESS=…` (beside :572's `REST_BIND_ADDRESS`); threaded through the Derived struct (:123-124, :167 region) and the template args (:610, :762). `rg -n "PostgrestBind" cli/` enumerates every touchpoint to mirror.
- **docker-compose.rest.yml:** `PGRST_ADMIN_SERVER_PORT: "3001"` in `environment:`; `"${REST_ADMIN_BIND_ADDRESS:?…}:3001"` added under `ports:` (same `:?` fail-fast idiom as :35).

**Security posture, stated plainly:** the admin endpoints become reachable from (a) the host's loopback — the same trust level as the main REST port today (and as `docker inspect`, which already reveals the container's env including `PGRST_JWT_SECRET`), and (b) the compose-internal network — where app/worker already hold same-or-higher-trust credentials. Nothing public: no Caddy route, no non-loopback host bind. This is strictly the existing REST-port posture applied to one more port.

### 2. Rewire the health check: readiness warmup *inside* `healthCheck`

The warmup goes at the **top of `healthCheck`** (exec.go:1292) rather than as a second call at the step-12 site — the pairing "functional probe is always preceded by readiness" becomes structural and cannot drift apart at future call sites. `healthCheck` has exactly one caller today (service.go:4036, verified), shared by both dispatch paths (service and inline both resume via applyPostSwap), and the install step-table has **zero** sibling RPC checks (verified by grep) — so this one site fixes every path.

Warmup loop (new `waitForRestReady(progress)` invoked first inside `healthCheck`):
- Resolve `REST_ADMIN_BIND_ADDRESS` from `.env` exactly as `healthURL()` resolves `REST_BIND_ADDRESS` (exec.go:1258-1282), with the same fail-fast actionable error if missing ("run `./sb config generate`").
- `GET http://<bind>/ready` every 2 s, HTTP client timeout 10 s. **200 → proceed** to the functional probe. **503 → keep waiting** (schema cache loading). **Connection refused/transport error → also keep waiting** (container still starting; no separate code path — the distinction matters only in the expiry message).
- **Cap: a new shared constant `RestReadyTimeout = 5 * time.Minute`.** Foreman floated 2-3 min; I pick 5 by the 012 budget doctrine — generous budgets on scaled work, because an under-budget readiness cap *manufactures* the exact failed-upgrade→rollback cascade this design removes, while the happy path exits in seconds and the failure path merely reports 2 min later. (King can trim to 3 m at ratification; the constant is one line.)
- **Watchdog interaction — the 031-class subtlety, explicit:** step 12 runs under applyPostSwap's progress-GATED ticker (armed :3785-3792; gate closes after `applyPostSwapStallThreshold` = 3 min of silence, watchdog.go:134). A silent 4-minute warmup would close the gate and get the unit SIGABRT'd. The loop therefore emits `progress.Write("Waiting for PostgREST readiness (schema cache loading, %s elapsed)…")` every ~15 s — each Write pings the watchdog (emitHeartbeat) and bumps the gate. This is doctrine-consistent: the loop is genuinely advancing (polling), output is its liveness signal, and it is bounded by its own timeout — exactly the gate-every-output-step / defer-only-silent-bounded principle.
- **On cap expiry → fail into `postSwapFailure` (no fallback), with the message distinguishing the two failure shapes:** never-got-an-HTTP-response (refused throughout) → "PostgREST admin server unreachable at <bind> after 5m — REST_ADMIN_BIND_ADDRESS stale or docker-compose.rest.yml missing the admin port; run `./sb config generate` and retry" (config drift); got-503s-but-never-200 → "PostgREST schema cache failed to load within 5m — check `docker compose logs rest`" (genuine readiness failure). Both actionable, both correctly trigger rollback.

The functional probe (`POST /rpc/auth_status`, 5×5 s) **stays unchanged after the warmup** — `/ready` proves PostgREST is warm; the RPC proves the anon request path end-to-end (the thing a migration can break). After `/ready`=200 the cold-cache PGRST002 is impossible at attempt 1; if a mid-check cache *reload* blips a 503, the existing 5×5 s absorbs it.

### 3. The weigh-question: mechanic's PGRST002-detect-and-wait as fallback? **No — dropped entirely.**

- After warmup, the race it patched cannot occur; keeping it is dead defensive code that future readers will mistake for a needed path (the remove-wrong-paths rule).
- A silent fallback when `/ready` is unreachable would *mask* exactly the regression class doc-006 taught us to fear (a future compose refactor drops the admin mapping → fallback engages → nobody notices the readiness signal is gone — a vacuous green). Unreachable-after-config-generate in the same pipeline is config corruption; fail fast with the actionable message above. The self-consistency that makes this safe: the binary that polls `/ready` ships in the same commit as the compose+config change, and applyPostSwap regenerates config (step 7) and recreates the rest container (step 11) *before* step 12 runs — the new check never probes an old compose config on the canonical path.

### Out of scope (named, not forgotten)

- **Container-level compose `healthcheck:` stanza** — orthogonal to the upgrade's signal (the Go-side poll narrates to the journal and feeds the watchdog; a compose healthcheck does neither) and depends on an in-image probe the distroless PostgREST image may not carry. Separate task if ever wanted.
- **Rollback's post-restore verification** (waitForDBHealth-only today) — 031's domain; rollback comes up at the OLD version where readiness semantics are the prior binary's business.
- **`/live`, `/config`, `/schema_cache`** — enabled as a side effect; nothing consumes them in this design.

## Verification (honest about what can't be VM-RED'd)

A deterministic VM RED for a schema-cache *race* is not honestly producible — we cannot stall PostgREST's cache loader without absurd scaffolding, and test-first-as-discovery says a rig-forced RED would prove the rig, not the bug. Instead:

1. **Unit tests (the real teeth):** httptest admin server driving `waitForRestReady` — 503×N→200 (waits, proceeds), refused→503→200 (transport errors tolerated), never-200 → cap expiry with the refused-vs-503 message distinction asserted; plus a structural test that `healthCheck` calls the warmup before the first functional POST (source-order style, the 012 guard-test pattern).
2. **Config tests:** derived `+6` port + `.env` line present (existing config test style).
3. **Regression net for free:** every post-swap harness scenario exercises the new warmup on every run — any green comprehensive run proves no regression.
4. **Observation GREEN at the sighting site:** the next dev-slot upgrade journal shows "Waiting for PostgREST readiness…" → "Health check OK" with **zero PGRST002** (the King's original observation, inverted).
5. **The scale-proof:** the rune-no canary deploy journal (real Norway schema) — the readiness wait's actual duration lands in the journal, replacing today's blind 25 s budget with measured truth.

## Critical files

- `docker-compose.rest.yml` (:5 image v12.2.8, :10-33 environment, :34-35 ports — the loopback idiom to mirror)
- `cli/internal/config/config.go` (:438-443 port offsets, +6 free; :499 the loopback bind pattern; :572 `.env` template; :123-124/:167/:610/:762 Derived struct + args threading)
- `cli/internal/upgrade/exec.go` (:1258-1282 `healthURL` — the resolution+fail-fast pattern to mirror; :1292-1330 `healthCheck` — warmup goes at the top)
- `cli/internal/upgrade/service.go` (:4010-4038 step 11→12 — call site unchanged; :3785-3792 the gated ticker the warmup must feed)
- `cli/internal/upgrade/watchdog.go` (:134 the 3-min gate threshold that makes the 15 s progress cadence necessary)

## Sequencing

King ratifies → implement (compose + config-gen + warmup + unit tests, one commit; small) → ships with the 031 fix in the gate-maker batch → observed GREEN on the next dev upgrade → scale-confirmed on the rune-no canary. Fits the doc-007 critical path without adding a step.
