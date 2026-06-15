---
id: STATBUS-061
title: >-
  legacy-recovery-lever: operator recovery entry re-stages the target binary
  from its image (closes the v2026.05.2-source preswap-checkout-kill wedge) —
  gated on install.sh acquisition
status: To Do
assignee:
  - architect
created_date: '2026-06-15 22:26'
updated_date: '2026-06-15 22:48'
labels:
  - upgrade
  - recovery
  - robustness
dependencies: []
references:
  - doc-011
  - install.sh
  - standalone.sh
  - cli/cmd/install_upgrade.go
priority: high
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design of record: doc-011 (Layer 3). Closes the residual the forward fix (STATBUS-060) cannot reach: an ALREADY-SHIPPED pre-fix binary (e.g. v2026.05.2) can't be patched, so a preswap-checkout-kill crash on such a source wedges (verified: v2026.05.2 runCrashRecovery dies at EnsureDBReachable on the down DB — no StartDBForRecovery fallback — before any compose call or rollback). Only escape: run a NEWER binary for recovery.

## CRUX — resolve FIRST (architect, file:line)
Does a stranded operator run a FRESH `install.sh` (curl'd latest) on recovery, or the PINNED on-disk one? Read install.sh (asset-curl ~:198-203), standalone.sh, and how operators bootstrap/recover (AGENTS.md: sole operator action is install.sh). This decides feasibility:
- **Fresh-curl** → the lever CAN reach legacy boxes. Implement it.
- **Pinned/bundled** → the legacy box can't receive the lever. Do NOT fake a solve: document the residual + exact manual recovery (`git checkout <OLD>` then `./sb install`) and stop.

## Lever (if feasible)
On a crashed-upgrade flag, the operator entry reads `flag.target` → `docker create ghcr.io/statisticsnorway/statbus-sb:<target_short>` + `docker cp <cid>:/sb ./sb` (same config-free image-extract as STATBUS-060) → runs the TARGET binary's recovery (emits the target's keys + has StartDBForRecovery) → DB comes up → rollback/resume proceeds. Preserves "operator just runs install.sh."

## Verification (foreman reviews + pushes)
- go build/vet/test green.
- Harness: the genuine-v2026.05.2-binary preswap-checkout-kill variant (STATBUS-026) RECOVERS via `./sb install` alone (no manual git surgery).
- Report the CRUX verdict + each commit SHA to the foreman before push.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 install.sh-acquisition verdict resolved with file:line (fresh-curl vs pinned)
- [ ] #2 If fresh-curl: lever implemented (operator entry re-stages target binary via docker create+cp, then runs target recovery); legacy genuine-binary variant recovers via ./sb install alone
- [ ] #3 If pinned: residual + exact manual recovery documented in doc-011; no fake solve
- [ ] #4 go build/vet/test green; reported to foreman before push
- [ ] #5 doc-011 Layer 3 updated with the verdict + outcome
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CRUX RESOLVED — install.sh acquisition is FRESH-CURL, not pinned (file:line): canonical operator/deploy action is `curl -fsSL https://statbus.org/install.sh | bash` (install.sh:4-8); both deploy drivers fetch it fresh every run — standalone.sh:66/231/245 and cloud.sh:46/530/551 (INSTALL_URL=https://statbus.org/install.sh). So a lever-carrying install.sh reaches a stranded box the moment the operator runs the canonical command. ⇒ the lever is FEASIBLE; do NOT take the documented-residual branch.

Bigger finding: install.sh ALREADY re-stages the binary in RESCUE mode — downloads the resolved-VERSION binary (install.sh:203) and `mv`s it over ./sb (209) BEFORE running ./sb install (269). So for a TAGGED target, a stranded v2026.05.2 box ALREADY recovers today via fresh `curl install.sh|bash` (it runs the target binary's recovery, which emits the keys + has StartDBForRecovery). The ONLY real gap: an EDGE/untagged target on a toolchain-free box — install.sh's edge path builds from source and needs `go` (install.sh:161-166, ./dev.sh build-sb at 190). Close it by giving install.sh the same image-extract as STATBUS-060 (docker create statbus-sb:<short> + docker cp /sb) → toolchain-free on all channels. So the 061 lever ≈ 'apply image-extract to install.sh's binary acquisition + (optionally) read flag.target for the exact target.'
<!-- SECTION:NOTES:END -->
