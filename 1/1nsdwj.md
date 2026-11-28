---
id: 1nsdwj
title: "StatBus runs sql_saga 1.15, with writer and time stamped per changed piece"
state: "doing"
type: chore
priority: "high"
assignee: ["rabbit"]
labels: []
group: ""
rank: "00000000000o"
created: 2026-11-22
updated: 2026-11-22
doing_since: "2026-11-26T21:28"
doing_with: "ca6dk5"
stage: "waiting"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
waiting_asked_by: "rabbit"
waiting_on: "rc.02 reaching Norway (owner: the Norway gate is the real-guest check)"
waiting_since: "2026-11-27T00:00"
---

## Goal
Every StatBus database runs sql_saga 1.15, upgraded from 1.6, with edit_by_user_id and edit_at as provenance columns.

## Purpose
sql_saga 1.9/1.10 bring provenance columns, so edit_by_user_id and edit_at are stamped per changed piece (k5q120); 1.11 stores numeric values exactly; 1.13-1.15 add era drop protection, one natural key value per entity and safe concurrent merges.

## Principle
One direct upgrade script from any release since 1.0; per database: new package, restart PostgreSQL, ALTER EXTENSION sql_saga UPDATE, SELECT sql_saga.check_integrity().

## Details
Today: postgres/Dockerfile ARG sql_saga_release=v1.6; every slot runs 1.6. Target v1.15 (7011af1, 2026-11-25), confirmed by the owner 2026-11-26. cli/cmd/db_restore_extensions.go (sqlSagaImagePins) gets 1.15 for the release after v2026.11.7-rc.01, whose first migration is 20261124114235; the migrate runner's extension step (cli/internal/migrate/extensions.go) updates 1.6 databases directly with sql_saga.check_integrity(). 1.9/1.10 add provenance columns: register edit_by_user_id and edit_at on every era so a changed piece records its writer and time. 1.15 changes temporal_merge (one natural key value per entity, ambiguous identity refused, entity locks); StatBus passes no delete_mode and no removed argument. Numeric rounding before 1.11 does not affect StatBus's numeric columns (percentage numeric(5,2), altitude numeric(6,1), lat/lng numeric(9,6)). Details per version: doc/upgrade.md in the sql_saga repo.

## Depends on

## Acceptance
- [ ] ~~The postgres image builds with sql_saga v1.12 and a migration runs ALTER EXTENSION sql_saga UPDATE; on a database upgraded from the last release extversion is 1.12 and SELECT sql_saga.check_integrity() reports no problem~~ (not relevant: superseded by the 1.15 checks 5-8 (owner chose 1.15, 2026-11-26), rabbit, 2026-11-26)
- [ ] ~~The fast SQL suite passes on 1.12~~ (not relevant: superseded by the 1.15 checks 5-8 (owner chose 1.15, 2026-11-26), rabbit, 2026-11-26)
- [ ] ~~A real-guest upgrade from the last release to a build with 1.12 succeeds (install/upgrade testing guide)~~ (not relevant: superseded by the 1.15 checks 5-8 (owner chose 1.15, 2026-11-26), rabbit, 2026-11-26)
- [x] [Owner] Confirms the target version (1.12 as the sql_saga agent said, or 1.13 tagged since); recorded here, and the other checks use that version
- [x] The postgres image builds with sql_saga v1.15; a database upgraded from the last release reports extversion 1.15 and SELECT sql_saga.check_integrity() reports no problem
- [ ] ~~A regular user's edit through a for_portion_of view stamps edit_by_user_id and edit_at on the changed pieces only (SQL test)~~ (not relevant: moved to sxbm3b, which activates provenance together with imports running as the uploader, rabbit, 2026-11-26)
- [x] The fast SQL suite passes on 1.15
- [x] A real-guest upgrade from the last release to a build with 1.15 succeeds (install/upgrade testing guide)

## Notes

2026-11-23 (Rabbit) Checked read-only: rune and dev both run sql_saga 1.6; the sql_saga repo has v1.12 at 676370d as stated, and since then v1.13 (a96e1cf, 2026-11-22 22:50: era drop protection, covering an era's checks, sync trigger and range column). The sql_saga agent's message said 1.12; whether StatBus takes 1.13 instead is the owner's or that agent's call.

2026-11-23 owner: take the latest sql_saga, but it is not ready yet: the owner found another issue there. Wait for the sql_saga release that fixes it; check 4 is answered by that version.


check 4: Owner 2026-11-26 20:33: target is sql_saga v1.15 (7011af1, 2026-11-25), the latest release. Preflight of 1.15 on the local slot's Norway copy (2.3 M units): no refusals, only the derived grants it carries over (tmp/1nsdwj/preflight-norway.log).
check 5: Image builds with sql_saga v1.15 (docker compose build db, 9 min). Local slot's Norway copy upgraded by ./sb migrate up: 'Extension sql_saga: 1.6 -> 1.15', extversion 1.15, db.extension_upgrade row 1.6->1.15, check_integrity clean, ~2 min (tmp/1nsdwj/migrate-up-norway.log). Pushed 7e99979ed.
landed 7e99979 on master 2026-11-26: postgres: pin sql_saga v1.15 (1nsdwj)
landed 182a7bf on master 2026-11-26: test: 002 and the security report list sql_saga 1.15's catalog (1nsdwj)
check 7: Fast SQL suite passes on 1.15: CI run on 182a7bfb7, Fast Tests success (the first run on 7e99979ed failed only on 002 and the security report, which list sql_saga's catalog; regenerated in 182a7bfb7). All other workflows green.
shipped in v2026.11.7 (7e99979)
check 8: Norway (rune) upgrade v2026.11.7-rc.02, 2026-11-28 10:21-10:36: sql_saga 1.6 -> 1.15 by ALTER EXTENSION UPDATE in 130 s (db log), all 21 migrations applied, upgrade complete and health verified; v2026.11.7 stable promoted on it. Log tmp/norway-rc02-progress.log.
## History
- 2026-11-26T21:28 todo -> doing/active (take with ca6dk5)
- 2026-11-27T00:00 doing/active -> doing/waiting (wait)
