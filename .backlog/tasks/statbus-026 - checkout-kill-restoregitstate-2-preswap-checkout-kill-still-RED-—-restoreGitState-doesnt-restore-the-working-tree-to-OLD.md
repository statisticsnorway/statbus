---
id: STATBUS-026
title: >-
  checkout-kill-restoregitstate: 2-preswap-checkout-kill still RED —
  restoreGitState doesn't restore the working tree to OLD
status: To Do
assignee: []
created_date: '2026-06-11 07:48'
updated_date: '2026-06-15 13:20'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COMMITTED ba02e1ed0 (pushed). Foreman verified the fix mechanism against product code: the pre-upgrade pin (git branch -f pre-upgrade HEAD, service.go:3806) runs BEFORE the target checkout (:3831), so the scenario's setup pre-checkout corrupts the pin to HEAD_LOCAL; restoreGitState (service.go:5341) resolves its previousVersion arg, falling back to pre-upgrade when it doesn't resolve (harness old version = v-stripped git-describe). Re-pin to OLD_COMMIT restores the production invariant (prod runs from a clean tree). Foreman correction at commit: the mechanic's comment named 'd.version' for the resolved ref — it's actually the 'previousVersion' argument (the OLD version, not the target); fixed in the committed comment for evidence accuracy. HARNESS-only. GREEN pending: confirmed by the comprehensive matrix harness run (operator drives once 027/029 + 031 scenario land).
<!-- SECTION:NOTES:END -->
