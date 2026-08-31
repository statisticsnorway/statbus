---
id: STATBUS-321
title: >-
  tcc-removal: retire the tcc installation — final backup, slot teardown, every
  reference swept (DNS already removed)
status: To Do
assignee:
  - architect
created_date: '2026-08-31 11:04'
updated_date: '2026-08-31 11:38'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Architect's execution plan (2026-08-31) — CORRECTED ORDER: QUIESCE → BACKUP → VERIFY-OFF-BOX → TEARDOWN → SWEEP.** Two corrections to the ticket's original order, with reasons: (1) QUIESCE FIRST — a backup taken while the upgrade service runs is a dump of a moving target, and the recovery machinery exists to bring a broken box BACK, so tearing down under it means fighting a system designed to undo exactly that; read the real unit names before stopping (list-units 'statbus*'), never guess. (2) VERIFY THE COPY THAT SURVIVES — the off-box copy must restore successfully on a DIFFERENT machine before teardown begins; a dump living only on tcc proves nothing about what outlives tcc. Sweep-after-teardown confirmed over sweep-before with the principle named: dead references produce loud failed jobs (noise that IS the unfinished-sweep signal), while sweep-first leaves a live unmanageable box acting unwatched — prefer the loud intermediate state. Sweep list: deploy-to-tcc.yaml, notify matrix entry, ops/niue/sshdoers lines, doc/CLOUD.md row (note offset 4 frees), GitHub deploy key, DNS — and the host Caddy change LAST with `caddy validate` before reload (an invalid reload takes down all nine remaining slots; the 283 hazard). Live /etc/sshdoers is a King root action by design. THREE PARAMETERS AWAIT THE KING: ${BACKUP_DEST} (where the terminal snapshot lives), ${BACKUP_RETENTION} (how long), ${REMOVE_UNIX_USER} (does statbus_tcc go entirely). Operator executes verbatim, foreman-gated per phase, the moment they land.

**King's parameters (2026-08-31), all three ruled:** ${BACKUP_DEST} = tmp/ on the King's own machine (nothing worth durable retention — the dump lands in the repo's local tmp/, e.g. tmp/tcc-final-backup/); ${BACKUP_RETENTION} = ~one week, the King deletes it himself; ${REMOVE_UNIX_USER} = YES, clean up entirely — his reasoning on record: an empty-shell user would force the next creation procedure to be idempotent with respect to pre-existing users, so full removal is the cleaner invariant. The backup still happens and still gets the off-box restore verification before teardown (the order is about trusting the copy that survives, however short its life). EXECUTION: operator runs the architect's phased list verbatim, foreman-gated per phase, QUEUED BEHIND Malawi's completion — one operator lane, and no niue host-level changes (Caddy validate/reload) while a create is mid-flight.
<!-- SECTION:NOTES:END -->
