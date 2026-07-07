---
id: STATBUS-143
title: >-
  install-recovery-db-route: crash recovery probes the DB by a different route
  than it connects — severed proxy becomes an unrecoverable error loop
status: To Do
assignee: []
created_date: '2026-07-07 02:27'
updated_date: '2026-07-07 04:46'
labels:
  - install-recovery
  - upgrade
  - product
  - recovery
dependencies: []
references:
  - cli/cmd/install_upgrade.go
  - cli/internal/upgrade/service.go
  - STATBUS-111
  - STATBUS-139
ordinal: 144000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: ./sb install recovery must reach the database the way the service does, or say precisely why it can't — a crashed upgrade must never become a dead end the operator's canonical action (run install again) cannot escape. BENEFIT: a crashed upgrade whose crash also took the proxy down stops being an unrecoverable error loop, and the reachability probe can never again pass against a path the real connection doesn't use. STAGE: Stage 1 (install/upgrade robustness). COMPLEXITY: engineer-substantial. DEPENDS ON: nothing.

FOUND live (rune-wedge scenario first run, 2026-07-07, kept-VM autopsy by the architect): the scenario accidentally created a crashed-upgrade state with the proxy container ABSENT — and install crash recovery dead-ended:

1. ROUTE MISMATCH: the connect-first pattern in the install ladder (install_upgrade.go Part 2) probes reachability via migrate's psql — docker-exec, straight into the db container — while LoadConfigAndConnect connects over TCP THROUGH the proxy (Caddy layer4 on CADDY_DB_BIND:PORT). With the db healthy but the proxy gone, the probe PASSES and the real connection then fails ("load upgrade config: listen connection: … connection refused") — the fallback start never fires because the probe said all was well. An observer that doesn't ride the observed route — the same defect class as the sessions-verdict fix, on a different pair of routes.
2. DEAD END: the start-fallback knows only `compose start db`; it can neither start a stopped proxy nor recreate a missing one, and the component that WOULD recreate it (applyPostSwap's service-recreate step) is unreachable because recovery can't connect. Every re-run of install hits the same wall — violating the "never a dead end" recovery contract (STATBUS-111).

REACHABILITY IN REALITY: plausible — a crash inside the service-recreate window can leave the proxy absent with the flag present; the operator then has no product-provided way out.

FIX SHAPE (architect): (a) probe the SAME route the connection uses (TCP via CADDY_DB_BIND:PORT), so probe-pass ⇒ connect-works by construction; (b) extend the asymmetric-safe start to `compose start db proxy` (start-existing only, never recreate); (c) for the truly-MISSING-proxy case, an actionable refusal naming the state and the operator action — never a silent identical error loop.

EVIDENCE: rune-wedge first run log (night pair 2026-07-07), kept-VM autopsy (db container up+healthy, proxy absent, .env CADDY_DB_BIND route confirmed); the scenario itself now keeps a stale-but-serving proxy (37f4305d2), so this state needs its own scenario when the fix lands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The recovery reachability probe uses the same route as the subsequent connection (probe-pass implies connect-works)
- [ ] #2 A crashed upgrade with a stopped-but-present proxy recovers autonomously (start-existing extended to the proxy)
- [x] #3 A crashed upgrade with a MISSING proxy produces an actionable named refusal, not a repeating identical error
- [ ] #4 A dedicated scenario drives the severed-proxy state once the fix lands
<!-- AC:END -->



## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-07 04:32
---
FIX-SHAPE RULING (architect, 2026-07-07 — the artifact the build keys on; same pattern as the 095/096 rulings).

THE EXACT MISMATCH, cited: EnsureDBReachable (exec.go:1198) probes via migrate.PsqlCommand — a psql that reaches the database CONTAINER directly (docker-exec transport) — while every real recovery connection (LoadConfigAndConnect → pgx) dials TCP through Caddy's layer4 route, CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT (the service's own DSN source, service.go:3222-3226). Two different roads to the same database: when the PROXY is absent or stopped, the probe passes against a healthy container while the connection refuses — observed live on the rune-wedge round-1 VM (db Up+healthy, proxy gone, 'load upgrade config: listen connection … 127.0.0.1:3014: connection refused' with no Part-2 fallback line, because the probe had already said 'reachable'). Second leg: the start-fallback (StartDBForRecovery) knows only `docker compose start db` — it can neither start a STOPPED proxy nor help a MISSING one, and the component that would recreate a missing proxy (applyPostSwap step 11) is unreachable because recovery cannot connect: a dead end on every install re-run, against the 111 never-dead-end contract.

THE SINGLE-SOURCE SHAPE (probe follows the connection — never the reverse; the TCP-via-proxy route is the production-real path the whole service is built on):
1. Extract ONE shared DSN/route builder from the service connect's requireKey(CADDY_DB_BIND_ADDRESS/CADDY_DB_PORT) block (service.go:3222-3226) — the single source of truth for 'how this box reaches its database'.
2. Rewrite EnsureDBReachable to dial THAT route: a 5s-bounded pgx connect + SELECT 1 on the shared builder's DSN. Delete the migrate.PsqlCommand probe path. Keep (and extend) the actionable error text: it should now name BOTH containers as the route ('the DB is reached through the proxy — check `docker compose ps` for db AND proxy') and keep the do-not-blindly-up-d guidance.
3. Extend the asymmetric-safe start to the ROUTE, not just the engine: StartDBForRecovery → `docker compose start db proxy` (start-only, never create/recreate — the rc.66→67 asymmetry holds for both; `start` on an already-running container is a no-op). A STOPPED proxy now resumes and recovery proceeds.
4. A MISSING proxy (removed, not stopped) stays a category-3 ACTIONABLE REFUSAL — named precisely ('the db's connection route — the proxy container — does not exist; the crash that interrupted this upgrade may have removed it mid-recreate'). Do NOT auto-recreate: `up -d proxy` under the operator's binary can image-mismatch the flag target (the rc.66→67 class). Recorded follow-up option, not built now: since the rune-wedge proof showed mismatched containers simply route resume through the full applyPostSwap recreate (forward, safe), a future King-blessed step could recreate the proxy deliberately; the refusal text may mention `docker compose up -d proxy` as the operator's manual option with the version caveat.

WHAT THIS CANNOT BREAK, checked: the STATBUS-136 abort branch (the other EnsureDBReachable consumer, service.go:6736) survives the route change because rollback()'s stop list is 'app worker rest db' — the PROXY deliberately stays up for the maintenance page — so the abort-time probe still passes on the real route (and rounds 3/4 of the abort oracle already prove that write lands). Exactly two consumers exist (install_upgrade.go:211/:216 + the abort site); both move to the new probe automatically.

TESTS THAT PIN IT: (a) UNIT — the shared-builder single-source is structural: assert EnsureDBReachable and the service connect both call the one builder (the postswap_test source-structure pattern), plus a behavioral unit: with CADDY_DB_BIND/PORT pointing at a dead port, EnsureDBReachable must FAIL even if a live postgres is reachable by other means — the exact false-pass this ticket kills. (b) SCENARIO (mechanic, after the product diff): the STOPPED-PROXY leg — fabricate the crashed shape (the rune-wedge preamble verbatim), `docker stop` the proxy (stop, not rm), run `./sb install`, assert: probe fails on the real route → the extended start-fallback starts db AND proxy (named log line) → recovery proceeds to completed. The missing-proxy refusal can be a cheap second phase on the same VM (rm the proxy post-completion … simpler: assert the refusal text in a unit test against the error constructor; a full VM phase for a refusal message is not worth a VM-hour).

WHO BUILDS: engineer (product diff — the shared builder + probe rewrite + start-extension + refusal text + unit tests), architect reviews before commit; mechanic builds the stopped-proxy scenario leg after the images build. No dependencies; buildable when the engineer frees up.
---

author: foreman
created: 2026-07-07 04:46
---
FIX SHIPPED 06cf8415f (2026-07-07), dual-reviewed (architect ship, three flags ruled; foreman first-hand; build+tests re-verified green after the final comment edit). The probe now follows the connection: recoveryDSN() single-sources the CADDY_DB_BIND route, EnsureDBReachable is a 5s pgx SELECT-1 on exactly it (docker-exec psql probe DELETED), StartDBForRecovery starts db+proxy (route-wide asymmetric-safe start), truly-missing proxy → named category-3 refusal with the up-d-image-mismatch caveat. ARCHITECT RULINGS: (1) proxyContainerMissing's structured ps -a probe BLESSED as REQUIRED surface — distinguishing missing-from-stopped via docker's error STRING would be text-as-classifier, the banned pattern; fail-open on ps-error is correctly biased toward letting a recovery that might work try. (2) Nested refusal placement accepted — the text stands alone, pinned by test. (3) Per-call .env read reclassified from cost to BENEFIT: the recovery ladder regenerates .env immediately before probing, so an init-cached DSN would dial the stale pre-regen route — a route-skew variant of the bug itself; comment added at recoveryDSN. REMAINING on this ticket: the mechanic's scenario leg (stopped-proxy green ride-along; severed-proxy refusal is unit-covered) + the auto-recreate follow-up stays a King-blessable product decision, deliberately not built.
---
<!-- COMMENTS:END -->
