---
id: STATBUS-084
title: >-
  preswap-recovery-nogo: PreSwap-phase self-heal should procure-or-error (not
  go-build) on a no-Go-toolchain box during crash recovery
status: To Do
assignee: []
created_date: '2026-06-18 01:34'
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
