---
id: STATBUS-143
title: >-
  install-recovery-db-route: crash recovery probes the DB by a different route
  than it connects — severed proxy becomes an unrecoverable error loop
status: To Do
assignee: []
created_date: '2026-07-07 02:27'
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
- [ ] #1 The recovery reachability probe uses the same route as the subsequent connection (probe-pass implies connect-works)
- [ ] #2 A crashed upgrade with a stopped-but-present proxy recovers autonomously (start-existing extended to the proxy)
- [ ] #3 A crashed upgrade with a MISSING proxy produces an actionable named refusal, not a repeating identical error
- [ ] #4 A dedicated scenario drives the severed-proxy state once the fix lands
<!-- AC:END -->
