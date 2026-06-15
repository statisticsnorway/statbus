---
id: STATBUS-058
title: >-
  postswap-config-drift: supervised upgrade daemon EnsureDBUp fails on post-swap
  boot when target release adds a mandatory compose var absent from the source's
  .env
status: In Progress
assignee: []
created_date: '2026-06-15 21:25'
updated_date: '2026-06-15 22:45'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FIX IMPLEMENTED + pushed to master as 87c38c4fb (supersedes first cut 133f239c3).

cli/internal/upgrade/service.go, Service.Run() — inside the in-flight-upgrade pre-flight block, BEFORE EnsureDBUp: regenerate config with the on-disk (target) binary so .env ⊇ the target compose template's required keys. Mirrors runCrashRecovery (cli/cmd/install_upgrade.go:164-170), the operator path that already handles this class (prior instance: COMMIT_SHORT / rc.62). Fatal on failure; config generate is DB-independent, idempotent, seconds (safe pre-READY=1).

GATE WIDENED (87c38c4fb vs 133f239c3): trigger is now ANY service-held flag (flag.Holder==HolderService), NOT just Phase==FlagPhasePostSwap. Reason: the binary-swap-kill sub-window leaves the TARGET binary on disk with a still-preswap flag (updateFlagPostSwap stamps post_swap only AFTER replaceBinaryOnDisk), so a post_swap-only gate would skip the regen and die identically, then boot-loop instead of reaching recoverFromFlag's rollback. The widened gate catches that sub-window (NEW binary is in control there, so the regen helps).

VERIFIED locally on 87c38c4fb: go build ./... clean, go vet ./... clean, go test ./internal/upgrade/ ./internal/install/ ./internal/config/ all pass.

VALIDATION IN FLIGHT: Images run 27578448988 building 87c38c4fb per-commit images; then install-recovery-harness 0-happy-upgrade dispatched against master. Pass criterion: the `ensure DB up: ... REST_ADMIN_BIND_ADDRESS is missing` death is GONE and upgrade reaches state='completed'. Operator driving.

SEPARATE/RESIDUAL (NOT covered by this fix): the preswap-checkout-kill window — crash AFTER `git checkout HEAD` but BEFORE the binary swap. There the OLD released binary restarts (lacks this code entirely) → its EnsureDBUp parses the HEAD working-tree compose → dies → recoverFromFlag (rollback) never reached. Verified against v2026.05.2 source (Run() order: EnsureDBUp strictly before recoverFromFlag; bare `docker compose up -d db`; PreSwap flag written before swap). Cannot be fixed in already-released binaries. This is the already-RED preswap-checkout-kill scenario (STATBUS-026); architect designing the fix (forward-fix executeUpgrade ordering vs make rollback reachable before any compose-parse). My earlier belief that the operator `./sb install` path recovers this window is UNVERIFIED and likely false (026: restoreGitState doesn't restore the working tree to OLD).

F1 evolution (the gate was too narrow, twice): 87c38c4fb gated the pre-EnsureDBUp config-regen first on Phase==post_swap, then broadened to any service-held flag (mechanic caught the binary-swap-kill window). BOTH still required a flag to EXIST. 0-happy (run 27578673237) FAILED: its Phase 3 restarts the unit onto the pre-staged HEAD binary BEFORE the upgrade flag is fabricated (Phase 4) → no flag → regen SKIPPED → EnsureDBUp parsed HEAD's compose against the stale v2026.05.2 .env → died on missing REST_ADMIN_BIND_ADDRESS (proof: the regen log line absent; the old 'ensure DB up ... REST_ADMIN_BIND_ADDRESS is missing' recurred at the Phase-3 restart). FIX: commit 7cc6c1b48 makes the regen UNCONDITIONAL before EnsureDBUp on every Service.Run startup (the binary can be ahead of .env with no flag — staged-binary restart, manual restart); flag read kept only for the diagnostic log. Matches runCrashRecovery's already-unconditional regen; idempotent/DB-independent/seconds/pre-READY. build+vet+upgrade/install/config tests green. Awaiting foreman byte-level review + push + 0-happy re-run. Does NOT touch runCrashRecovery (operator path).
<!-- SECTION:NOTES:END -->
