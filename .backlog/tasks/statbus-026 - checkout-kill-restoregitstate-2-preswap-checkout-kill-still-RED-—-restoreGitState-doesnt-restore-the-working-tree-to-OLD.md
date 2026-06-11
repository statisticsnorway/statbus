---
id: STATBUS-026
title: >-
  checkout-kill-restoregitstate: 2-preswap-checkout-kill still RED —
  restoreGitState doesn't restore the working tree to OLD
status: To Do
assignee: []
created_date: '2026-06-11 07:48'
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
