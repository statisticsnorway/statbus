---
id: STATBUS-151
title: >-
  seed-restore-missing-admin: pg_restore "role admin_user does not exist" in
  three 22:39-22:46 runs — distinct, unexplained, quarantined
status: To Do
assignee: []
created_date: '2026-07-08 23:42'
labels:
  - ci
  - testing
  - investigation
  - quarantined
dependencies: []
references:
  - STATBUS-150
  - postgres/init-db.sh
priority: low
ordinal: 152000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: no unexplained failure mode rides a closing ticket into invisibility — this one gets its own resolution or its own artifact-closure.
> STAGE: QUARANTINED behind the King's manual-intervention answer (asked in the 2026-07-09 morning report). If he confirms hand-intervention on the test host in the window, this likely closes as artifact; if he denies it, this becomes a live investigation with clean evidence.

OBSERVED: three pg_regress runs — on 46e30276a, 12083f237, 81e102a5c (22:39–22:46, 2026-07-08) — failed with pg_restore: error: could not execute query: ERROR: role "admin_user" does not exist → "Error: seed restore: pg_restore reported errors (transaction rolled back; database unchanged): exit status 1". In the same window, STATBUS-150's mode 1 (the PGDATABASE seed-guard refusal) STOPPED reproducing with NO relevant commit in 2577373fa..46e30276a (checked over dev.sh, cli/internal/migrate/, cli/cmd/migrate.go) — the co-occurrence suggests the test host's state changed outside git.

REFUTED HYPOTHESIS (architect's fold, refuted by the mechanic's mode-3 trace, 2026-07-09): this is NOT downstream of an init-db abort at init-db.sh:187 — admin_user is created by the exception-safe DO-blocks at :157-160, which PRECEDE :187 and are immune to ON_ERROR_STOP by construction; an :187 abort cannot produce a cluster missing admin_user. Distinct mechanism required.

EVIDENCE POINTERS: gh runs on the three commits above (pg_regress workflow, 2026-07-08T22:39–22:46Z); STATBUS-150's diagnosis notes for the surrounding timeline; the mechanic's mode-3 walk (150 notes) for the init-db section map.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The King's manual-intervention answer is recorded here (yes → close as artifact with the doctrine restated; no → promote to live investigation)
- [ ] #2 If promoted: the mechanism producing a cluster/restore-target without admin_user is named from evidence, not presumed
<!-- AC:END -->
