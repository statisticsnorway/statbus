---
id: STATBUS-059
title: >-
  preswap-checkout-forward-fix: image-extract sb procurement + defer the
  working-tree checkout to close the preswap-checkout-kill window at the source
status: To Do
assignee: []
created_date: '2026-06-15 22:10'
labels:
  - install-recovery
  - upgrade
  - recovery
  - procurement
  - architect-plan
  - king-decision
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/Dockerfile.sb
  - .github/workflows/images.yaml
  - cli/cmd/seed.go
  - install.sh
  - cli/cmd/install_upgrade.go
  - test/install-recovery/scenarios/2-preswap-checkout-kill.sh
priority: high
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DESIGN-OF-RECORD — pending KING REVIEW (foreman brings it after the post-swap-config-drift 0-happy run lands). No code yet. Splits into impl tasks after the King rules the decisions below.

## North Star
The supervised upgrade must converge to healthy (or clean rollback) with the operator's ONLY action being `./sb install` — never custom commands (per STATBUS-039). Today a crash in the upgrade's checkout-then-binary-swap window breaks that.

## Root cause
`executeUpgrade` does `git checkout <target>` (service.go:3831) BEFORE the binary handoff. The only reason the checkout must precede the swap is that edge procurement (`buildBinaryOnDisk`, `make -C cli build`, service.go:5507) builds from the checked-out source. Once the working tree holds the target's compose, ANY `docker compose` call config-load-parses the whole merged project (docker-compose.yml `include:`s docker-compose.rest.yml) and dies on a newly-mandatory `${VAR:?}` (REST_ADMIN_BIND_ADDRESS, added by STATBUS-032) that the still-in-control pre-target binary's .env lacks.

## Core forward-fix (closes the window for fixed-release sources)
Two coupled changes, both in the new binary's code:
1. Procurement → image-extract. Replace `buildBinaryOnDisk`'s `make` with `docker create ghcr.io/statisticsnorway/statbus-sb:<commit_short>` + `docker cp /sb ./sb` — config-free (no compose/.env), no host Go/make. Mirrors the existing `./sb db seed fetch` (cli/cmd/seed.go:160-179). The `statbus-sb` image already ships on every master push (images.yaml matrix; distroless, commit-addressable; cli/Dockerfile.sb). `replaceBinaryOnDisk` (tagged, service.go:5428) already needs no checkout.
2. Defer the checkout. Since (1) makes procurement checkout-independent, move `git checkout <target>` out of executeUpgrade's pre-swap section into the new binary's `applyPostSwap`, just before config-generate (service.go:4115). The old binary then never leaves the tree at target-compose.

Interplay with the post-swap config-regen fix (STATBUS-058, committed 87c38c4fb): keep it. It regenerates config before EnsureDBUp and covers the new-binary instant between applyPostSwap's checkout and its config-generate. Complementary; together airtight for fixed-release sources.

## Corrected residual — genuine pre-fix source is a real wedge (verified)
A genuine v2026.05.2 binary driving the upgrade is NOT `./sb install`-recoverable in this window. Proof (git show v2026.05.2:cli/cmd/install_upgrade.go): runCrashRecovery = config generate (L121) → EnsureDBReachable connect-only (L137) → RETURNS on failure (L138); it has NO StartDBForRecovery fallback (post-v2026.05.2). The DB is STOPPED in the window (backup stop, upstream of the checkout), so EnsureDBReachable fails and the git rollback (RecoverFromFlag, L153) is NEVER reached — it wedges at the connect-only check, before any compose call. This violates STATBUS-039.
Mitigation option (legacy lever): the operator entry, on a crashed-upgrade flag, re-stages the TARGET sb binary from the image BEFORE recovery, then runs the target binary's runCrashRecovery — which DOES recover (config-generate emits the keys at install_upgrade.go:168 before StartDBForRecovery's compose-start at :193). install.sh today curls a fixed-VERSION release asset (install.sh:198-203); the change = fetch the flag's target via the image.

## Test fidelity
2-preswap-checkout-kill PRE-STAGES HEAD's sb (upload_sb_to_vm, scenario:122) and recovers with it → it validates HEAD-recovery, NOT the genuine pre-fix wedge. (restoreGitState itself WORKS — `git checkout -f previousVersion`, service.go ~5392; the prior RED was a harness pre-upgrade mis-pin, fixed ba02e1ed0.)

## KING DECISIONS (gate the split)
- D1 Procurement scope: unify ALL procurement to image-extract (retire `make`-build AND the release-manifest path `replaceBinaryOnDisk`) — simplest/uniform/no-toolchain — vs NARROWER: image-extract for edge only + defer-checkout for the tagged path, leaving the manifest path.
- D2 Legacy wedge: accept (document a one-time manual recovery) vs mitigate (legacy lever).
- D3 Harness fidelity: add a genuine-pre-fix-binary recovery variant so 026 stops masking production reality?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A toolchain-free host (no Go/make) completes both an edge-commit and a tagged-release upgrade end-to-end (sb procured by image-extract)
- [ ] #2 No git checkout of the target leaves the working tree at the target's compose while a pre-target binary remains systemd's restart target (verified by harness)
- [ ] #3 The post-swap config-regen fix (STATBUS-058) is preserved and shown complementary to the deferred checkout
- [ ] #4 King ruling D1 (procurement scope: unify vs narrower) recorded before implementation
- [ ] #5 King ruling D2 (legacy v2026.05.2 wedge: accept vs mitigate via the legacy lever) recorded
- [ ] #6 King ruling D3 (026 genuine-pre-fix recovery variant: yes/no) recorded
- [ ] #7 If D2=mitigate: operator `./sb install` on a crashed preswap-checkout flag recovers with no custom commands, by re-staging the target binary from the image
<!-- AC:END -->
