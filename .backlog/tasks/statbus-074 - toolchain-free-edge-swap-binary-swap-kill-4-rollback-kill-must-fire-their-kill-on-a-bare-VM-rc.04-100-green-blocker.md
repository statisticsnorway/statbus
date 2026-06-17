---
id: STATBUS-074
title: >-
  toolchain-free-edge-swap: binary-swap-kill + 4-rollback-kill must fire their
  kill on a bare VM (rc.04 100%-green blocker)
status: In Progress
assignee:
  - mechanic
created_date: '2026-06-17 11:04'
labels:
  - install-recovery
  - harness
  - rc.04
  - gate
  - critical-path
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - test/install-recovery/scenarios/2-preswap-binary-swap-kill.sh
  - test/install-recovery/scenarios/4-rollback-kill.sh
  - doc/install-upgrade-testing.md
priority: high
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE concrete fix the King's "hold for 100% green" bar puts on the rc.04 critical path. Predicted by STATBUS-073's "LATENT SECOND LAYER" analysis; to be CONFIRMED by run 27683157288 (the run is the oracle — see doc/install-upgrade-testing.md).

GOAL (plain): two install-recovery scenarios — test/install-recovery/scenarios/2-preswap-binary-swap-kill.sh and 4-rollback-kill.sh — must actually fire their injected kill at the binary-swap point on a bare Hetzner VM, so they exercise real interrupted-upgrade recovery instead of silently no-op'ing.

MECHANISM (predicted, verify from code): both swap to an EDGE target. The edge-swap path runs buildBinaryOnDisk = `make -C cli build` (cli/internal/upgrade/service.go ~4018/4032), which FAILS toolchain-free on the bare VM -> procureErr -> rollback (~4036) BEFORE inject.KillHere (~4048). So the kill never fires -> the scenario fails ("inject did not fire" / "flag absent after kill"). This second layer was MASKED by the quiesce-rollback bug (STATBUS-073) until the SIGKILL-quiesce fix (3a0d6e6dd) unmasked it.

FIX DIRECTION: route the edge-swap through a toolchain-free path — image-procurement / docker-pull of a pre-built binary, OR target a tagged release that already carries the inject framework — so the swap COMPLETES and inject.KillHere fires. This is also a small down-payment on STATBUS-071 (real throwaway-branch images), per the King's "build from real images, not fabrication" direction; keep the rc.04 fix MINIMAL (just enough to make these two green), framework stays parked in 071.

OWNER: mechanic (investigate + draft now, HELD — do not commit until run 27683157288 confirms the exact failure signature). Foreman reviews + commits.

RELATED: STATBUS-073 (gate-residual umbrella / root-cause), STATBUS-028 (4-rollback-kill's SEPARATE rc=75 rollback-tolerance layer, already committed 3b986a2d0), STATBUS-026 (checkout-kill fidelity), STATBUS-071 (real-image framework this prefigures).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 #1 make-fail mechanism confirmed-or-refuted from code with exact file:line (edge-swap buildBinaryOnDisk on a toolchain-free VM)
- [ ] #2 #2 the existing working toolchain-free swap pattern identified (how succeeding swap scenarios get their target binary without `make`)
- [ ] #3 #3 minimal fix landed: edge-swap routed through the toolchain-free path so the swap completes and inject.KillHere fires
- [ ] #4 #4 both scenarios GREEN in a comprehensive install-recovery run (the run is the oracle)
- [ ] #5 #5 fix kept minimal; full real-image framework left parked in STATBUS-071
<!-- AC:END -->
