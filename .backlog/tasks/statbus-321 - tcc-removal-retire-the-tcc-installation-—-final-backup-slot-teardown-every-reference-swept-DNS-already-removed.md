---
id: STATBUS-321
title: >-
  tcc-removal: retire the tcc installation — final backup, slot teardown, every
  reference swept (DNS already removed)
status: To Do
assignee:
  - architect
created_date: '2026-08-31 11:04'
labels:
  - ops
  - cloud
dependencies: []
priority: high
type: task
ordinal: 314000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the tcc installation ceases to exist cleanly — its data preserved once, its slot torn down, and no workflow, roster, or doc left pointing at a ghost. King's directive 2026-08-31: tcc.statbus.org's DNS is already removed; the installation follows.

SCOPE, to be planned precisely before any destructive act (this is a production slot with real data — backup-first is non-negotiable):
1. FINAL BACKUP: a full database dump of statbus_tcc, archived somewhere durable and named as the slot's terminal snapshot (the King rules retention: where and for how long).
2. SLOT TEARDOWN on niue: stop and remove the slot's containers/volumes, the systemd user units, and (King's call) the statbus_tcc unix user + home. The exact teardown steps get an architect-reviewed command list BEFORE execution — cloud.sh wipe is DB-recreate, not slot removal; no existing verb does full retirement, so the list is bespoke and runs operator-hands with foreman gating.
3. REFERENCE SWEEP, the non-destructive half (buildable immediately): remove statbus_tcc from cloud.sh's SERVERS roster; delete .github/workflows/deploy-to-tcc.yaml (its deploy branch is already unwritten since STATBUS-244; note the STATBUS-248 Wave-D1 caution about deleting receive paths applies only to boxes that still exist — a removed installation has no receive path to strand); sweep doc/CLOUD.md and any sshdoers/allowlist entries naming tcc; check ops/inspect-cloud-installations.sh and credentials records.
4. VERIFY: cloud.sh status shows no tcc; niue carries no statbus_tcc processes; the terminal snapshot is readable.

ORDER: backup FIRST and verified readable, then teardown, then sweep — never interleaved. The King is exempting tcc from the fleet's v2026.08.0 convergence run precisely because it is leaving.

WHAT IS ACHIEVED: the fleet's roster matches reality, and the departed installation leaves exactly one artifact — its final backup.
<!-- SECTION:DESCRIPTION:END -->
