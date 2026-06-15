---
id: STATBUS-027
title: >-
  midtx-kill-assertion: 3-postswap-mid-tx-kill still RED — advanced past
  stall-detection to an upgrade-row-state assertion failure
status: In Progress
assignee:
  - mechanic
created_date: '2026-06-11 07:48'
updated_date: '2026-06-15 13:21'
labels:
  - install-recovery
  - harness
dependencies: []
priority: medium
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run 27306718138 @ cd2f5d51f: 3-postswap-mid-tx-kill FAIL. The mechanic's tonight fix (new wait_for_midtx_stall_ready polling pg_stat_activity for the parked migration backend, since the inline dispatch path has no migrate subprocess for pgrep, + an || true fence on the masking pipeline) cleared the stall-not-firing layer, but the scenario then failed at a LATER assertion: "rc=1 at assertions.sh:50" reading the upgrade row state (SELECT state FROM public.upgrade ORDER BY id DESC LIMIT 1). HARNESS, 0 product. Investigate: did the SIGKILL of the host-side docker-exec PID actually kill the in-container migration backend (docker-exec signal forwarding), and what state did the upgrade row end in vs what the scenario asserts? May need to assert against the actual post-recovery state on the inline path. Does NOT block the RC cut.
<!-- SECTION:DESCRIPTION:END -->
