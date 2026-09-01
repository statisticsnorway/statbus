---
id: STATBUS-084
title: >-
  preswap-recovery-nogo: Self-heal must get the sb binary from Docker (pull
  image, or build in-container) — never host `go build`. Fixes the 4 no-compiler
  install tests + a real Albania wedge.
status: Done
assignee: []
created_date: '2026-06-18 01:34'
updated_date: '2026-07-03 10:46'
labels:
  - upgrade
  - recovery
  - hardening
  - robustness
dependencies: []
references:
  - 'cli/cmd/root.go:127'
  - 'cli/cmd/root.go:152'
priority: medium
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT: When crash recovery runs `./sb install` and the on-disk binary is "stale" vs the working tree, the freshness self-heal (cli/cmd/root.go) tries to REBUILD the binary (`go build -o ../sb`). On a box with no Go toolchain, that fails ("rebuild failed: exit status 2"). root.go:152 handles the service-held POST-SWAP case (procure-or-error), but the PRE-SWAP recovery path is not covered — it falls through to `go build`.

WHY: a no-remote-access, no-Go-toolchain production box (e.g. Albania installs via install.sh + docker, no Go) that ever reaches a self-heal-needed state during a PreSwap-phase crash recovery would hit the un-buildable `go build` instead of procuring the matching image or erroring cleanly. It is NOT reachable on the canonical paths today: production install.sh procures a MATCHING binary (no staleness → no rebuild), and the rc.04 recovery TEST will pin via install.sh --commit (STATBUS-082) so the harness never hits it either. So this is a latent robustness gap, surfaced during the rc.04 install-recovery triage (run 27724641822, the recovery freshness-rebuild unmask). Architect-identified.

STATUS / NON-GATING: not required for the rc.04 cut (install.sh --commit sidesteps it in the test; production procures a matching binary). This task hardens the product self-heal so a genuinely-stale PreSwap recovery on a toolchain-less box degrades gracefully.

FIX SHAPE: extend the PreSwap-phase self-heal (root.go around :127-152) so that when a rebuild would be needed AND no Go toolchain is present, it PROCURES the matching image (the same path root.go:152 uses post-swap) or fails with an actionable error — never an un-buildable `go build` on a no-Go box.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TRACK A CONFIRMED (engineer + foreman, 2026-06-18). This is THE fix for the 4 freshness reds (backup/binary-swap/checkout/4-rollback-kill) AND a real latent Albania bug — promoted from non-gating to gating. ROOT (verified file:line): freshness self-heal rebuild.go:37 runs HOST `make -C cli build`→`go build`; no host Go → exit 2 → "Self-heal rebuild/exec failed". Fires from stalenessGuard (root.go:159) for selfheal cmds (install/upgrade service/apply-latest) when ./sb is stale vs tree. The toolchain-free procure path ALREADY exists: install.sh edge (install.sh:198-203, pull-then-docker-build-in-container fallback) + Service.procureSbFromImage (service.go:5622, pull-only, LACKS the build fallback). FIX (engineer design, tmp/engineer-build-architecture.md): extract one shared `sbimage.Procure(projDir, commitSHA, sbPath)` = pull→in-container-build-fallback→create+cp+chmod; self-heal calls it (target=worktree HEAD) instead of make; procureSbFromImage delegates to it (gains the fallback). Nuance: pushed commit→image exists; unpushed dev commit→in-container build ~30s (same tradeoff edge accepts). Awaiting King nod before engineer implements.

IMPLEMENTED + COMMITTED + PUSHED as 75c0dd9d5 (foreman-reviewed full diff). New cli/internal/sbimage primitive (pull → in-container-build-fallback-gated-on-HEAD==target → create+cp+chmod); freshness/rebuild.go make→sbimage.Procure (keeps re-exec + SelfHealAttemptEnv); upgrade/service.go procureSbFromImage delegates (gains build fallback, no 0-happy-upgrade regression); cmd/root.go comments/strings only, logic unchanged. go build/vet + freshness/upgrade unit tests clean. NOT Done — the 4 scenarios going green is proven only by the install-recovery harness run; re-fire batched with the mid-tx (027) + two-scenario fixes.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-03 10:46
---
CLOSED — already shipped in code; verify-and-close per the King-ratified consolidation (Cluster 6). Evidence (operator-verified 2026-07-03): commit 75c0dd9d5 on master; the self-heal path procures the sb binary via sbimage.Procure/ProcureShort (service.go:6298-6299) — no host `go build`. Residual operator-advice strings tracked separately in STATBUS-085 (docs sweep cluster).
---
<!-- COMMENTS:END -->
