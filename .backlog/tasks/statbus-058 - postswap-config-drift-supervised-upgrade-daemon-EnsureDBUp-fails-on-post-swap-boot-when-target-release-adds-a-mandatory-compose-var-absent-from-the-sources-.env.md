---
id: STATBUS-058
title: >-
  postswap-config-drift: supervised upgrade daemon EnsureDBUp fails on post-swap
  boot when target release adds a mandatory compose var absent from the source's
  .env
status: To Do
assignee: []
created_date: '2026-06-15 21:25'
labels:
  - upgrade
  - robustness
  - install-recovery
  - product-bug
dependencies: []
priority: high
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Summary

The supervised upgrade-service daemon cannot BOOT after a post-swap handoff when the **target** release introduced a new mandatory (`${VAR:?}`) docker-compose variable that the **source** release's `.env` does not contain. The daemon's startup `EnsureDBUp` runs `docker compose up -d db`, which interpolates the WHOLE merged compose model (not just the `db` service), so a missing mandatory var in ANY service (here `REST_ADMIN_BIND_ADDRESS` in the rest service) aborts the call. config-generate — the only thing that would add the new var — runs LATER in `applyPostSwap`, so the daemon exits 1 and systemd restart-loops before recovery can proceed.

## Empirical confirmation (CI run 27560968218, headSha 96df2e9b3, scenario 0-happy-upgrade)

```
statbus-upgrade-statbus[75229]: Error: ensure DB up: docker compose up -d db: exit status 1
(error while interpolating services.rest.ports.[]: required variable REST_ADMIN_BIND_ADDRESS
 is missing a value: REST_ADMIN_BIND_ADDRESS must be set in the generated .env)
```

The HEAD binary booted cleanly (no staleness-guard/rebuild path hit — daemon-startup SHA-fix 31db8cec0 is confirmed working) and failed precisely at the mandatory-var interpolation.

## Verified evidence chain (file:line + reproduced)

1. `docker-compose.yml` uses `include:` → merges `docker-compose.rest.yml` (and app/worker/postgres/caddy). So `EnsureDBUp`'s bare `docker compose up -d db` (no `-f`) auto-loads all of them.
2. `docker-compose.rest.yml:45` → `${REST_ADMIN_BIND_ADDRESS:?REST_ADMIN_BIND_ADDRESS must be set in the generated .env}` (mandatory).
3. Isolated repro: `docker compose config db` (targeting ONLY db) with the var unset FAILS with the identical "required variable ... is missing" error — compose interpolates the whole merged model, not just the targeted service.
4. `REST_ADMIN_BIND_ADDRESS` does NOT exist at `v2026.05.2^{}` (50fd4325, 2026-05-21); added by commit 9257eadc7 (2026-06-15, UNRELEASED — no tag contains it). Only HEAD's config-generate emits it (derived default). So a v2026.05.2 `.env` cannot contain it.
5. `cli/internal/upgrade/exec.go:1160-1168` — `EnsureDBUp` runs `docker compose up -d db`.
6. `cli/internal/upgrade/service.go:1479` — `Service.Run()` calls `EnsureDBUp` (unconditionally) BEFORE `connect → recoverFromFlag → resumePostSwap → applyPostSwap`.
7. `cli/internal/upgrade/service.go:4112-4118` — `applyPostSwap` step 1 runs `./sb config generate` (the only thing that adds the new var) — AFTER EnsureDBUp.

## Scope

- **Affected:** supervised upgrade-service path (systemd `statbus-upgrade@.service` → Service.Run → EnsureDBUp). Manifests only on the post-swap boot (stale `.env`); normal restarts have a matching `.env` and pass.
- **NOT affected (to confirm with architect):** the inline `./sb install` path reaches `applyPostSwap` directly, whose step-1 config-generate runs BEFORE its first compose call (step 9 db up). Operator-driven `runCrashRecovery` uses `EnsureDBReachable` (connect-only psql SELECT 1), not `docker compose up` — exec.go:1153-1159, 1217.
- **Not bitten in production** because 9257eadc7 is unreleased — the harness caught it before any upgrade crossed the boundary.

## Proposed fix (F1 — pending architect refinement + King review; product code → King reviews design first)

On the post-swap recovery boot in `Service.Run()`, regenerate config with THIS (target) binary BEFORE `EnsureDBUp`, gated on the post-swap flag already detected at service.go:1474-1478. This makes `.env` ⊇ the target compose template's required vars before any compose call, aligning with EnsureDBUp's own doc intent (exec.go:1148-1151: "uses the in-flight target's compose template"). config-generate is DB-independent and idempotent; applyPostSwap's config-generate stays. Rejected F3 (make the var non-mandatory) — abandons the deliberate fail-loud-on-config-drift design (exec.go:1313-1337).

## Status
- Diagnosis: COMPLETE, empirically confirmed (foreman, independent of architect).
- Verdict: (B) real product robustness gap — NOT a scenario gap. The 0-happy scenario faithfully reproduces it; do NOT add config-generate to the scenario (would mask the bug). Mechanic stood down off the (A) scenario fix.
- Fix design: with architect for refinement; King reviews before implementation.
<!-- SECTION:DESCRIPTION:END -->
