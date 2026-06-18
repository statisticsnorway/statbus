---
id: STATBUS-074
title: >-
  toolchain-free-edge-swap: The 4 'no host compiler' recovery tests must pass on
  a bare VM (backup-kill, binary-swap-kill, checkout-kill, 4-rollback-kill)
status: In Progress
assignee:
  - mechanic
created_date: '2026-06-17 11:04'
updated_date: '2026-06-18 08:23'
labels:
  - install-recovery
  - harness
  - rc.04
  - gate
  - critical-path
dependencies:
  - STATBUS-084
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PREMISE REFUTED AT CODE LEVEL (mechanic investigated; foreman independently verified from cli/internal/upgrade/service.go on master; routed to architect for adversarial cross-check). The predicted `make -C cli build` toolchain-free make-fail DOES NOT EXIST: buildBinaryOnDisk (5660-5682) either SKIPS via sbAlreadyAtCommit (5664 -> nil, the case here since the harness pre-stages HEAD's sb via upload_sb_to_vm) or pulls a PREBUILT image via procureSbFromImage (5699-5741: docker pull/create/cp from ghcr.io/statisticsnorway/statbus-sb:<short>; doc at 5691 = 'no host Go/make toolchain'). The `make -C cli build` text is ONLY in two STALE comments (1424, 4018). sbAlreadyAtCommit EXISTS (5763). So the path is sbAlreadyAtCommit=true -> nil -> inject.KillHere (4048) -> exit 137 BY DESIGN. => NO toolchain-free-swap fix is needed; ACs #1-#3 (build a fix) are MOOT. RE-SCOPED: this task now tracks 'CONFIRM binary-swap-kill + 4-rollback-kill go GREEN on run 27683157288; if RED the cause is NOT procurement — diagnose the state-detection fork (Detected install state: line) + whether SIGKILL quiesce held the service down (systemd auto-restart re-claiming the fabricated row).' Kept OPEN, not closed: the run is the oracle (doc/install-upgrade-testing.md), analysis alone does not prove green. Architect to correct STATBUS-073's two now-falsified notes + assess the two open questions from code.

ARCHITECT ADVERSARIAL VERIFY = CONFIRMS the refutation (2026-06-17). No separate fix needed; the SIGKILL quiesce (3a0d6e6dd) is likely the whole fix for these two. WHEN run 27683157288 LANDS, read the oracle lines for binary-swap-kill + 4-rollback-kill: 'Detected install state:' must = scheduled-upgrade (NOT db-unreachable / nothing-scheduled) AND 'first install exited:' must = 137 (NOT 0/1) -> PASS. If 'db-unreachable' recurs -> quiesce didn't fully prevent the rollback (re-open open-Q i); if 'nothing-scheduled' -> a re-claim slipped through. This task closes as 'no fix needed, confirmed by run' if both go green; otherwise it becomes the diagnosis tracker for the actual fork.
<!-- SECTION:NOTES:END -->
