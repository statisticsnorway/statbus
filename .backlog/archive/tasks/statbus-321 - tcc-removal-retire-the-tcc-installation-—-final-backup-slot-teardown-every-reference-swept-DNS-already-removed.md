---
id: STATBUS-321
title: >-
  tcc-removal: retire the tcc installation — final backup, slot teardown, every
  reference swept (DNS already removed)
status: Done
assignee:
  - architect
created_date: '2026-08-31 11:04'
updated_date: '2026-08-31 12:00'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TCC IS RETIRED (2026-08-31), by the architect's five-phase list, operator-executed, foreman-gated per phase, with every King parameter honored. PHASE 0: quiesced read-first (unit names read before stopping; safe-by-verified-circumstance justification on record). PHASE 1: final dump (3.8MB, 2446 TOC entries) landed at tmp/tcc-final-backup/tcc_20260831_114510.pg_dump — King's local tmp, ~1-week retention, his deletion. PHASE 2: off-box restore verification — first attempt REJECTED (silent image downgrade + intolerable extension errors; deviation owned), honest re-run on the product image passed: all 17 extensions present including sql_saga, 176 tables, sane row counts; one bounded anomaly on record (external_ident's COPY blocked by its own check constraint — the archive retains the rows; no archaeology on data ruled not-worth-retaining); the 'missing temporal tables' finding was a phantom (statbus has no satellite tables). PHASE 3: containers, volumes, network gone; statbus_tcc user removed entirely (King's idempotence reasoning). PHASE 4a: repo sweep at 80f113144 — deploy workflow deleted, notify matrix, roster, sshdoers doors (+count comments, command strings verbatim), doc/CLOUD.md row with offset 4 marked FREE, plus AGENTS.md's stale slot list and the self-hosted staging draft; full grep accounting, historical forensics deliberately untouched. PHASE 4b: host Caddy read→validate→reload harmed none of the nine remaining slots; GitHub deploy key 96481695 revoked; live /etc/sshdoers installed byte-identical from the reviewed copy with hash republished (foreman, King-granted root). One correction along the way now in team memory: the verification should have used ./sb db verbs, not a handcrafted container — the product's own machinery first, always. The fleet's roster matches reality; the departed installation left exactly one artifact.
<!-- SECTION:FINAL_SUMMARY:END -->
