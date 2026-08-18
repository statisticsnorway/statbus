---
id: STATBUS-228
title: >-
  rollback-restore-crash: upgrades can no longer roll back — the service
  crash-dies twice during the rollback's database restore, on two scenarios that
  passed before
status: To Do
assignee:
  - engineer
created_date: '2026-08-18 10:27'
updated_date: '2026-08-18 10:35'
labels:
  - upgrade-recovery
  - release
  - regression
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - tmp/operator-arc-fails34-triage-2026-08-18.md
priority: high
type: bug
ordinal: 228000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When an upgrade fails, the system's promise is that it rolls back: restore the database backup, restart the old version, leave a working box. At rc.03, that promise broke — and a release cannot ship while rollback is broken, because rollback is what makes every other upgrade risk survivable.

WHAT THE EVIDENCE SHOWS: two arc scenarios that exercise rollback (restore-broke-reattempt, jobs 95644094935; rollback-pair-terminal, 95644095093) both got through setup and into their rollback phase, then failed identically: "ROLLBACK_FAILED_DB_RESTORE: rollback could not complete — two consecutive crash-deaths during rollback (recovery attempt 1)", with the database connection dying mid-restore ("failed to receive message: unexpected EOF" on 127.0.0.1:3014). Both scenarios PASSED at the previous full suite (run 30755799405). The two failures are byte-identical in signature, 13-15 minutes into healthy runs — not the VM-starvation class (that one is 227).

THE SUSPECT WINDOW: everything between the last passing suite's commit and the rc.03 tag (bafcb396b) — which includes the recent restore/read-only-window work, the marker-truth rewrite on the restoration success arm, and the restore-identity changes. The crash-death-during-restore shape suggests the service process itself is dying while the restore runs (watchdog kill? panic? the restore's own connection handling?) — "two consecutive crash-deaths" is the budget guard's counting language, meaning the daemon died and its resume died again.

WHAT IS ACHIEVED BY FIXING: the promotion path reopens on a release whose rollback demonstrably works — the one property an unattended statistical-office box cannot live without.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Root cause traced with file:line — what in the suspect window makes the service crash-die during the rollback DB restore
- [ ] #2 Fix designed (architect-reviewed) and landed with a RED-first oracle at the unit level where the mechanism allows
- [ ] #3 Both scenarios green at a suite run carrying the fix — the promotion candidate moves to that release
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-18 10:35
---
**ROOT CAUSE TRACED (AC#1). VERDICT: PRODUCT BUG, not scenario drift. Two defects, both from 21ec09911 (STATBUS-197, 2026-08-16) — verified an ancestor of rc.03 (bafcb396b). Full trace: tmp/engineer-228-trace-2026-08-18.md. No fix designed — architect's diagnosis gate first.**

**THE SERVICE NEVER CRASHED UNEXPECTEDLY.** Both arcs INJECT the deaths they report: "two consecutive crash-deaths during rollback" is the product's own designed terminal for the `(rollback, rollback)` step pair these arcs engineer on purpose, and each kill marker was verified consumed by the arc itself. The `unexpected EOF` is not a crash either — it is a connect attempt against a database the product deliberately stopped one second earlier. No SIGABRT, no panic text anywhere in either 400KB log; the triage's three hypotheses are refuted.

**WHAT ACTUALLY FAILED — one assertion each, same upstream fact:** rollback-pair-terminal — `recovery_attempts=3` not confirmed (log 4965); restore-broke-reattempt — the STATBUS-111 re-attempt legend never printed (log 4568), because `StateRestoreReattemptable` needs `state='failed' AND backup_path IS NOT NULL` (service.go:3761, :8247) and the row shows `"backup_path": null` (log 4921).

**DEFECT 1 — the row's backup_path write targets a STOPPED database. Deterministic: every upgrade, every box.** :5587-5588 stops the DB (hard step — "rsync of a running Postgres data dir is NOT crash-consistent"); :5618 takes the cold backup; then **:5638** runs `terminalExec("UPDATE public.upgrade SET backup_path = …")` against that stopped server:
```
M 10:17:51 Stopping database… / Container statbus-test-db Stopped
M 10:17:52 Backing up database…
M 10:18:00 Warning: could not record backup_path … failed to connect … unexpected EOF
```
`terminalExec` (:7959) is teardown-immune against a dying CONNECTION (154/163) — it opens a fresh one. It cannot conjure a stopped SERVER. 197 moved this write here; it previously ran early as intent via `d.queryConn.Exec` with a ping/reconnect, while the DB was up.

**BLAST RADIUS EXCEEDS THE TWO ARCS.** A later write at :6402 sets backup_path once the forward path reconnects — so a SUCCESSFUL upgrade looks fine. The column is NULL exactly when the upgrade dies before that point: the crash/rollback population STATBUS-111 exists for. **`./sb install` can no longer re-attempt a failed restore on any box**, and the pending probe at :3761 counts zero forever. The comment at :5627-5637 claims both carriers hold the identity and "backup_path == '' ⇔ nothing moved" is exact — one carrier is structurally dead, and the invariant now reads FALSE in the dangerous direction.

**DEFECT 2 — a PreSwap flag now carries a BackupPath, falsifying the recovery branch's premise.** 197 stamps the FLAG at the same moment (:5641) with the phase UNCHANGED — its own comment says "still old-sb-upgrading" (:5634-5635). The PreSwap branch is built on the opposite: ":1315-1318 — a PreSwap flag carries an empty BackupPath … restoreDatabase refuses to touch the volume"; ":1348-1349 — empty by construction at PreSwap". Both now false. Observable: the branch prints "The database was not modified, so nothing needs restoring … no snapshot recorded" (:1342, log 10:18:25), then twelve seconds later logs `Restoring database from backup at …/pre-upgrade-active` (log 4855, 4896). A PreSwap rollback that was a database no-op is now a full destructive restore cycle — data-neutral in content, but a large new failure surface on exactly the path these arcs kill into.

**WHY THIS IS NOT SCENARIO DRIFT.** rollback-pair-terminal's header states the invariant in the product's own words: "the DB COLUMN backup_path is set during the very first dispatch's backup step … independent of flag.BackupPath, **which IS empty on this route**". The scenarios assert what the product's comments STILL claim; the product changed underneath its own documentation.

**ONE THREAD NOT FULLY TRACED, flagged not guessed:** `recovery_attempts=1` vs 3. The pair-terminal fired correctly (it keys on the on-disk step pair the arc verified formed). The count is second-order — recovery now routes through the PreSwap "nothing changed" branch rather than the counted path the choreography assumed. Needs one more pass; changes neither root cause nor fix shape.

**FIX SHAPE for the ruling (not implemented):** (1) the row write must happen where the DB is reachable — my read: make the existing post-reconnect write at :6402 the single row recorder, letting the FLAG carry the identity across the DB-down gap; (2) the PreSwap premise must be restored (flag stamp moves past the swap boundary) or :1300-1353's argument and message rewritten for a world where a PreSwap flag carries a snapshot identity — a semantics call. RED-first oracle without a VM: a source pin that no `public.upgrade` row write sits between the `stop db` step and the DB restart in `executeUpgrade`.
---
<!-- COMMENTS:END -->
