---
id: STATBUS-151
title: >-
  seed-restore-missing-admin: pg_restore "role admin_user does not exist" in
  three 22:39-22:46 runs — distinct, unexplained, quarantined
status: To Do
assignee: []
created_date: '2026-07-08 23:42'
updated_date: '2026-07-09 00:05'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RECURRENCE OUTSIDE THE QUARANTINED WINDOW: run 28983725043 (03b0dba26, 2026-07-08 23:50) hit the same mode — db container went Healthy, then seed restore failed with pg_restore 'role admin_user does not exist' (Command was: CREATE POLICY activity_admin_user_manage...). This is ~70 minutes after the quarantined 22:39-22:46 cluster, on an image containing 03b0dba26's [1/8] validation refuse. Weakens the pure manual-intervention-artifact theory — the mode reproduces under current code. Candidate mechanism to test when promoted: a fresh volume whose FIRST boot aborts EARLY in init-db (e.g. the new [1/8] refuse under the still-present host collision, or any pre-:157 abort) leaves a cluster with NO admin_user; the restart boots it healthy ('Skipping initialization'); if the test flow then creates the app database itself, everything proceeds until the seed pg_restore needs the missing cluster-level role. Under that mechanism this mode is the collision's OTHER downstream — the abort-point decides which symptom appears: late abort (:187) → roles present, wait-race unhealthy (150 mode 3); early abort ([1/8] refuse or earlier failure) → healthy-but-roleless cluster → this pg_restore mode. The 23:50 run fits: 03b0dba26's refuse fires at [1/8] on the collision-carrying host, before the roles block. If that holds, this closes as ANOTHER collision downstream once the workflow self-heal (b2a5cbe8e) actually runs — blocked right now by the 3-second SSH failure under diagnosis on STATBUS-150.
<!-- SECTION:NOTES:END -->
