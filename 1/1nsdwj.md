---
id: 1nsdwj
title: "StatBus runs sql_saga 1.12"
state: todo
type: chore
priority: "high"
assignee: []
labels: []
group: ""
rank: "00000000000n"
created: 2026-11-22
updated: 2026-11-22
---

## Goal
Every StatBus database runs sql_saga 1.12 (tag v1.12, commit 676370d), upgraded from 1.6 by a migration, with check_integrity clean.

## Purpose
sql_saga 1.12 brings provenance columns for edit_by_user_id and edit_at (k5q120) and fixes numeric rounding in temporal_merge before 1.11. Message from the sql_saga agent 2026-11-22, relayed by the owner.

## Principle
One direct upgrade script from any release since 1.0; per database: new package, restart PostgreSQL, ALTER EXTENSION sql_saga UPDATE, SELECT sql_saga.check_integrity().

## Details
Today: postgres/Dockerfile ARG sql_saga_release=v1.6; the test slot reports extversion 1.6. cli/internal/migrate/extensions.go and the restore table (release first migration -> sql_saga version) must learn 1.12. Rounding check: before 1.11 temporal_merge could round large or high-precision numeric values (12345678901234567890.123 -> 12345678901234567000), unrepairable after the fact. StatBus's numeric columns on temporal tables are legal_relationship.percentage numeric(5,2), location.altitude numeric(6,1), latitude and longitude numeric(9,6): all far below the precision where rounding occurs, so no data check is needed. Details per version: doc/upgrade.md in the sql_saga repo.

## Depends on

## Acceptance
- [ ] The postgres image builds with sql_saga v1.12 and a migration runs ALTER EXTENSION sql_saga UPDATE; on a database upgraded from the last release extversion is 1.12 and SELECT sql_saga.check_integrity() reports no problem
- [ ] The fast SQL suite passes on 1.12
- [ ] A real-guest upgrade from the last release to a build with 1.12 succeeds (install/upgrade testing guide)
- [ ] [Owner] Confirms the target version (1.12 as the sql_saga agent said, or 1.13 tagged since); recorded here, and the other checks use that version

## Notes

2026-11-23 (Rabbit) Checked read-only: rune and dev both run sql_saga 1.6; the sql_saga repo has v1.12 at 676370d as stated, and since then v1.13 (a96e1cf, 2026-11-22 22:50: era drop protection, covering an era's checks, sync trigger and range column). The sql_saga agent's message said 1.12; whether StatBus takes 1.13 instead is the owner's or that agent's call.

2026-11-23 owner: take the latest sql_saga, but it is not ready yet: the owner found another issue there. Wait for the sql_saga release that fixes it; check 4 is answered by that version.
