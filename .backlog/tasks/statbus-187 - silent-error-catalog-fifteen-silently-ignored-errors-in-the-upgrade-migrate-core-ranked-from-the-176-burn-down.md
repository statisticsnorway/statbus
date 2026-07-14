---
id: STATBUS-187
title: >-
  silent-error-catalog: fifteen silently-ignored errors in the upgrade/migrate
  core, ranked (from the 176 burn-down)
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-07-14 19:23'
updated_date: '2026-07-14 20:39'
labels:
  - fail-fast
  - upgrade
  - defect
  - install-recovery
dependencies: []
priority: medium
ordinal: 188000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: no error in the upgrade/migrate core is silently dropped where its failure changes what the operator or the recovery machinery believes. The 176 errcheck burn-down made every ignore EXPLICIT with an inline concern-comment; this ticket is the catalog of the fifteen whose proper handling is a behavior change needing individual rulings — the 185 pattern, second wave.
> ORIGIN: STATBUS-176 batch 2 (mechanic, 2026-07-14); each site carries its concern inline in code. Architect severity review pending on the top three.

RANKED (mechanic's ordering, architect to confirm/amend):
TOP — masks a second failure or risks live-service consistency:
1. service.go rollback() ABORT branch: restoreDatabase error dropped — DB volume can be left inconsistent while the terminal reports only ROLLBACK_FAILED_GIT_CORRUPT.
2. service.go ReattemptRestore + rollback() normal path: pre-restore `docker compose stop` ignored — the volume rsync can proceed against live services.
3. service.go executeUpgrade CI-not-ready unschedule: returns nil regardless of whether the row-reset UPDATE landed — silent failure leaves the row wedged/unclaimable.
STALE-FLAG CLASS (failed unlink → a later boot misreads crashed/in-progress): 4. removeUpgradeFlag (both sites); 5. ReleaseInstallFlag; 6. post-swap self-heal completion flag Remove.
ONE-SHOT AT BOOT: 7. cleanStaleMaintenance Remove — failure leaves the site in maintenance (Caddy 503) until the next daemon restart.
LEDGER DIVERGENCE (migrations): 8. migrate.go two `DELETE FROM db.migration` in the down path; 9. full-rollback DROP TABLE/SCHEMA leftover.
BOUNDED/SELF-RETRYING: 10. recoverFromFlag corrupt-flag + stale-install-flag removes (retry next boot).
COSMETIC/SELF-CORRECTING: 11. exec.go backup/log prune RemoveAlls; 12. periodic-poll UPDATEs + PostgREST NOTIFYs (self-correct next cycle).

SHAPE: fix in ranked waves (top-3 first, as their own reviewed unit with arc/regression coverage where the paths are arc-covered — #1 and #2 sit exactly on restore paths the restore-broke-reattempt arc exercises); stale-flag class as one uniform treatment; tail may be accepted-and-documented. Every fix replaces its explicit-ignore marker.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect confirms/amends the ranking and rules the handling per tier (hard-fail / loud-warn / accept-documented)
- [ ] #2 Top-3 fixed as their own reviewed unit, proven by the arcs that cover those paths
- [ ] #3 Stale-flag class gets one uniform ruled treatment
- [ ] #4 Every fixed site's explicit-ignore marker is replaced; accepted sites keep a ruling-citing comment
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman (relaying architect)
created: 2026-07-14 19:41
---
ARCHITECT RANKING REVIEW (2026-07-14, from the batch-2 pass) — AC#1's ranking half done, handling rulings included: TOP-3 REORDERED to #2 > #1 > #3. (2) pre-restore compose-stop ignored (both restore paths) is the HIGHEST consequence — a silently-failed stop means rsync-restoring the volume UNDER a live postgres: a torn-restored-volume data-corruption pathway. Low likelihood, cheap principled fix: a verify-stopped guard before the rsync. FIRST FIX UNIT, medium. (1) ABORT-branch restoreDatabase error dropped — real fail-loud gap but on a human-summon path with no autonomous consumer (the progress line lies to support, not machinery); fix = capture + fold into the ABORT error string. Low-med, second wave. (3) CI-not-ready unschedule returning nil — ledger-honesty bounded by retry-tick semantics; rides the family. None of the three blocks rc.06/stable per the architect — but the King's all-install-upgrade-tickets gate makes the top-3 unit part of the stable list regardless (his rule governs).
---

author: foreman
created: 2026-07-14 19:51
---
Fix unit #2 DISPATCHED to mechanic (2026-07-14 evening): verify-stopped guard before the rsync at BOTH pre-restore stop sites (ReattemptRestore + rollback() normal path) in cli/internal/upgrade/service.go — capture the compose-stop error AND positively verify services are down before any volume rsync; hard-fail actionably if not (never rsync under a live postgres). Shared helper, explicit-ignore markers replaced at fixed sites (AC#4). Scope strictly #2; #1/#3 second wave. Behavioral oracle after commit: the restore-broke-reattempt arc (covers these exact paths). Mechanic freezes for foreman review; engineer concurrently owns test/install-recovery/ for the 071 no-delta variant — file ownership disjoint.
---

author: architect
created: 2026-07-14 20:21
---
DESIGN RULING on unit #2's frozen diff (architect, 2026-07-14; the mechanic executes this mechanically and refreezes). Verdict per decision:

1. NEW ABORT TIER — APPROVED as built, names and all. Reusing ROLLBACK_FAILED_GIT_CORRUPT would lie to support (that code is documented git-only; the name must carry the actual danger class — the name-the-danger doctrine). Retry-then-abort is REJECTED: after a verified-failed stop, re-running the same `docker compose stop` is self-heal-flavored guessing on a data-safety boundary (no-standing-self-heal); the tolerance for SIGTERM grace belongs in the GUARD's bounded re-check (ruling 2), not in a second stop. state='failed' + the rollback_aborted callback event is correct — same class as the git-corrupt ABORT: degraded box, human summoned, nothing unwound. Firing BEFORE restoreGitState is the right boundary (zero mutations). The 4th terminal-write site + the structural pin 3→4 with symmetric guards/removes is exactly how that contract test is meant to move. Names approved: ErrRollbackServicesNotStopped / ROLLBACK_FAILED_SERVICES_NOT_STOPPED / failed-abort-services-live.

2. GUARD CONTRACT — the foreman's fail-closed inversion is RIGHT, plus a bounded re-check:
- ALLOW-LIST, not deny-list: a service passes ONLY when absent from `ps -a` output or in state exited / created / dead. ANY other state — running, restarting, paused, removing, or a state string we don't recognize — FAILS, naming the service and its observed state verbatim. Rationale: this guard defends a data-corruption boundary; unknown states must not pass by default (a paused postgres still holds the volume open; restarting cycles through non-running instants; docker may add states).
- BOUNDED RE-CHECK: poll the allow-list at 1s intervals up to a 30s budget (compose stop's default SIGTERM grace is 10s; 30s covers a configured longer grace with margin) — pass the moment all services qualify; on budget exhaustion fail naming the stragglers + states. Never unbounded: a hung dockerd must reach the ABORT.
- HOME: cli/internal/compose, exported (e.g. compose.VerifyStopped(projDir, services, budget)), next to QuiesceClients/ResumeClients — the stopped-state classification table lives ONCE; the JSON ps parsing moves with it. compose's existing quiesce-side running-check (compose.go:~195) serves a different decision (whether to stop) and stays as-is.

3. SITE 1 (ReattemptRestore) — APPROVED with ruling 1's prefix. Correct that it writes NO terminal: the function returns the error, the row STAYS failed + backup_path → still reattemptable — the re-attempt is retryable by design.

4. MECHANICAL: (a) move the helper out of ReattemptRestore's doc+func unit (never split a doc comment); (b) one shared services identifier PER SITE feeds BOTH the stop command's args and the verify call — the stop-set and verify-set must be the same object so they cannot drift.

INTERACTIONS, resolved:
- StateRestoreReattemptable routing is SANE IN BOTH HALVES — verified: the row's backup_path is written at backup completion (service.go:5219), so a POST-backup ABORT row matches the probe (state.go:273) and `./sb install` routes to ReattemptRestore — which now stops AND VERIFIES (site 1) before restoring: the error text's own remedy ("./sb install") is literally the designed fix loop. A PRE-backup ABORT row (rollback invoked with backupPath "") has no row backup_path → no match → nothing-scheduled refresh; row stays honestly failed; remedy = re-trigger — unchanged semantics.
- Monitoring/callbacks: additive — the event stays rollback_aborted (existing consumers fire), the new code string is a new member of an existing family.
- DOCS, in the same unit: doc/upgrade-timeline.md's terminal table gains the row (new tier + both remedy halves above); doc/upgrade-vocabulary.md gains the code/label if its tables enumerate them.

ORACLE: unit tests — the classification table (fake ps outputs: running/restarting/paused/unknown → fail named; exited/created/dead/absent → pass; straggler-then-clears within budget → pass) + the updated structural contract; the restore-broke arc's next natural re-run covers site 1's happy path. NO dedicated VM arc: constructing a genuinely stuck container requires docker-daemon manipulation out of proportion to a branch that byte-mirrors the arc-proven git-corrupt ABORT shape.
---

author: foreman
created: 2026-07-14 20:38
---
FIX UNIT #2 COMMITTED (foreman, 2026-07-14 evening): commit 3d7cf6b22 — compose.VerifyStopped (exported, fail-closed allow-list exited/created/dead/absent, 1s poll × 30s budget, probe under a context deadline so a hung dockerd surfaces at budget), ps-JSON parsing relocated to compose (PsEntry/ParsePsJSON) with all upgrade-package callers updated; ReattemptRestore returns actionably prefixed ROLLBACK_FAILED_SERVICES_NOT_STOPPED with NO terminal write (row stays reattemptable — the error's own ./sb install remedy is the designed fix loop); rollback() normal path gets the NEW ABORT tier (failed-abort-services-live) mirroring git-corrupt, firing before restoreGitState; structural pin 3→4; one shared preRestoreStopServices at both sites; classification unit tests (injected probe + real NDJSON); doc/upgrade-timeline.md third terminal tier + states-table cross-ref. Architect ruled the design (comment #3); mechanic executed; foreman line-reviewed twice and verified build/vet/test independently. Both explicit-ignore markers replaced (AC#4 progress). Remaining for AC#2: ranked #1 (ABORT-branch restoreDatabase error — ruled: capture + fold into the ABORT error string) and #3 (CI-not-ready unschedule — handling shape needs one architect line). Oracle: restore-broke-reattempt arc's next natural re-run.
---

author: architect
created: 2026-07-14 20:39
---
RANKED #3 SHAPE RULED (architect, 2026-07-14): HARD-FAIL, not loud-warn — check the Exec error AND RowsAffected on the unschedule UPDATE (service.go:~5073); on either failure call d.markPgInvariantTerminal (the established genre for ledger-write failures, same as promoteExistingCandidate:4231) and RETURN THE ERROR, never nil; the "unscheduled" progress line moves AFTER the confirmed reset so the log cannot lie. Correction to my comment-#1 bounding: "retry-tick semantics" was too generous — a wedged in_progress row is NOT retried by discovery ticks (they skip in_progress); only boot-time completeInProgressUpgrade reconciles it, which is exactly why the failure must be loud at the moment it happens. RowsAffected==0 (row concurrently changed/vanished) takes the same loud path.
---
<!-- COMMENTS:END -->
