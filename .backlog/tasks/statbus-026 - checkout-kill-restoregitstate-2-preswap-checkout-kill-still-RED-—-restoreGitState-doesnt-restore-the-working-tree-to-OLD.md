---
id: STATBUS-026
title: >-
  checkout-kill-fidelity: 2-preswap-checkout-kill validates HEAD-recovery only
  and MASKS the genuine v2026.05.2-binary wedge (restoreGitState exonerated;
  harness-pin fixed ba02e1ed0)
status: In Progress
assignee:
  - mechanic
created_date: '2026-06-11 07:48'
updated_date: '2026-06-15 22:15'
labels:
  - install-recovery
  - harness
dependencies: []
priority: medium
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run 27306718138 @ cd2f5d51f: 2-preswap-checkout-kill FAIL. The mechanic's tonight fix (capture SB_VERSION_BEFORE AFTER upload_sb_to_vm) landed and cleared the binary-version layer, but a DEEPER red surfaced: "✗ working tree not restored to OLD (cd2f5d51f vs 50fd4325f) — restoreGitState path broken" (rc=137 at 2-preswap-checkout-kill.sh:154). The scenario kills during checkout; on recovery, restoreGitState is supposed to put the working tree back to the OLD (pre-upgrade) version, but it stays at the run SHA (cd2f5d51f). HARNESS, 0 product. Likely shares a root with STATBUS-028 (4-rollback-kill also hits a restoreGitState abort, rc=75). Investigate the restoreGitState path (pre-upgrade branch pin / git checkout -f to OLD) — relates to the R1 pre-upgrade-branch-pin requirement and possibly STATBUS-021 (VM-script transport). Does NOT block the RC cut.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 HEAD-recovery path: 2-preswap-checkout-kill green in the comprehensive matrix run (ba02e1ed0)
- [ ] #2 restoreGitState confirmed NOT the root cause (exonerated + documented)
- [ ] #3 NEW genuine-v2026.05.2-binary variant added that exposes the EnsureDBReachable down-DB wedge (no HEAD pre-stage)
- [ ] #4 Chosen legacy-recovery fix (per King-approved design) makes the genuine-binary variant recover via the operator's only action (./sb install)
- [ ] #5 Cross-referenced with STATBUS-058 and the deeper defer-checkout/image-procurement design
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Current state (verified this session, 2026-06-15)

restoreGitState is EXONERATED — it works (`git checkout -f previousVersion`, service.go:~5392). The original RED ("working tree not restored to OLD") was a HARNESS bug: the scenario's setup pre-checkout corrupted the `pre-upgrade` branch pin (git branch -f pre-upgrade HEAD at service.go:3806 runs BEFORE the target checkout at :3831 → pinned HEAD_LOCAL, the fallback ref restoreGitState uses). FIXED in ba02e1ed0 (harness re-pins `pre-upgrade` to OLD_COMMIT). The title's old "restoreGitState doesn't restore" framing is SUPERSEDED.

## NEW finding (this session) — the scenario tests the WRONG binary

2-preswap-checkout-kill.sh:122 `upload_sb_to_vm` PRE-STAGES HEAD's sb and recovers with it → exercises HEAD's runCrashRecovery, which RECOVERS (HEAD config-generate emits REST_ADMIN_BIND_ADDRESS + has a StartDBForRecovery fallback that brings the stopped DB up). It does NOT exercise a genuine v2026.05.2 operator, which WEDGES:

- In the checkout→swap window the DB is STOPPED (backup stop, upstream of the checkout; not restarted till applyPostSwap).
- v2026.05.2 runCrashRecovery (verified `git show v2026.05.2^{}:cli/cmd/install_upgrade.go`): config generate (121, OLD binary can't emit the new var) → EnsureDBReachable (137, connect-only psql) → FAILS on the down DB → returns immediately (138). NO StartDBForRecovery fallback (absent in v2026.05.2). RecoverFromFlag/restoreGitState (153) NEVER reached.
- ⇒ genuine v2026.05.2→(mandatory-var-adding target) crash in this window is a WEDGE, not `./sb install`-recoverable. The current scenario's GREEN (HEAD-recovery) MASKS this.

Related: STATBUS-058 (config-drift bug + F1 fix 87c38c4fb covering the post-swap & binary-swap-kill windows). This preswap-checkout-kill window is the residual F1 does NOT cover.

## What "done" requires (gated on King's design decision)

Architect is writing the design doc (defer the working-tree checkout into applyPostSwap, enabled by image-based binary procurement; + a legacy recovery lever that re-stages the TARGET binary on the operator entry so `./sb install` recovers via a key-emitting binary). KING REVIEWS the shape before any code. Then: add a faithful genuine-v2026.05.2-binary variant exposing the wedge; implement the chosen fix; assert recovery via the operator's only action. NOT self-sufficient yet — completion depends on the King's design decision.

## Prior note (retained)
COMMITTED ba02e1ed0 (pushed) — harness pre-upgrade re-pin to OLD_COMMIT. Foreman-verified against product code. HARNESS-only fix. HEAD-recovery GREEN pending the comprehensive matrix run. Does NOT block the rc.03 cut (residual is documented; deeper fix is rc.04 per foreman lean, King to decide).
<!-- SECTION:NOTES:END -->
