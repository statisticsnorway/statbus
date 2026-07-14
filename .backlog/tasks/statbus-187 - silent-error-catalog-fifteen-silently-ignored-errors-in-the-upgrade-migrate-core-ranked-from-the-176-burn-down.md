---
id: STATBUS-187
title: >-
  silent-error-catalog: fifteen silently-ignored errors in the upgrade/migrate
  core, ranked (from the 176 burn-down)
status: Done
assignee:
  - '@mechanic'
created_date: '2026-07-14 19:23'
updated_date: '2026-07-14 21:10'
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
- [x] #2 Top-3 fixed as their own reviewed unit, proven by the arcs that cover those paths
- [x] #3 Stale-flag class gets one uniform ruled treatment
- [x] #4 Every fixed site's explicit-ignore marker is replaced; accepted sites keep a ruling-citing comment
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

author: foreman
created: 2026-07-14 20:46
---
SECOND WAVE COMMITTED — TOP-3 UNIT COMPLETE (foreman, 2026-07-14 evening): commit 792300943. Ranked #1: rollback()'s git-corrupt ABORT branch captures its restoreDatabase error and folds the outcome into rollbackFailedMsg + progress log (succeeded / ALSO FAILED: <err>) — same tier/code/label/event/flow. Ranked #3: executeUpgrade's CI-not-ready unschedule HARD-FAILS per the architect's comment #4 ruling — Exec error AND RowsAffected==0 both route through markPgInvariantTerminal (promoteExistingCandidate byte-pattern) and return the error, never nil; the 'unscheduled' progress line moved after the confirmed reset. Both markers replaced. AC#2 CHECKED: all top-3 fixed as reviewed units (3d7cf6b22 wave 1 + 792300943 wave 2), proven by unit tests + the structural contract; the restore-broke-reattempt arc covers the restore paths on its next natural re-run. Remaining on this ticket: AC#3 (stale-flag class uniform treatment — needs an architect ruling) and AC#4's accepted-sites half (tail sites keep ruling-citing comments once the tail is ruled).
---

author: architect
created: 2026-07-14 20:48
---
STALE-FLAG CLASS RULED (architect, 2026-07-14) — AC#3, one uniform treatment, no per-site deviation: LOUD-WARN, never hard-fail, with ENOENT-as-success.

WHY LOUD-WARN IS THE HONEST TIER FOR THIS CLASS (and hard-fail would be wrong):
1. Severity inversion: all three sites are cleanup-AFTER-terminal — the terminal write already landed, the row is honest, the work SUCCEEDED. Hard-failing there converts a successful upgrade/rollback conclusion into a reported failure because a janitorial unlink failed — the punishment lands on the wrong actor.
2. The consequence is a BOUNDED availability wedge, not corruption, and the bound is existing machinery: a persisting flag makes the next dispatch read crashed-upgrade → the ghost-flag/reconcile path runs → which itself re-attempts the removal — every boot retries, nothing accumulates silently. (This is the same reasoning that accepted ranked #10 as bounded; the difference here is these sites get the WARN because the operator deserves the signal at the moment it happens, not a silent extra recovery pass later.)
3. A filesystem that persistently refuses unlink (EROFS, EACCES, IO) is a box-level problem every other path will also scream about; the warn names it first.

THE UNIFORM SHAPE (mechanic executes):
- The treatment lives INSIDE the flag-owning functions, not at call sites: removeUpgradeFlag (covers both its callers), ReleaseInstallFlag, and the post-swap self-heal completion Remove routed through the same pattern (through removeUpgradeFlag itself if it isn't already).
- ENOENT IS SUCCESS: `os.IsNotExist(err)` → no warn (a benign double-removal race must not cry wolf). Every OTHER error → one loud line naming (a) the path, (b) the error verbatim, (c) the CONSEQUENCE ("the next ./sb install will read this box as crashed-upgrade and run a harmless recovery pass"), (d) the REMEDY ("investigate why the file could not be removed; remove it manually"). Log/progress loudness — NOT the siren (no park, no degraded state).
- AC#4 at these sites: the explicit-ignore markers are replaced by the warn + a comment citing this ruling.
- ORACLE: unit-level — assert ENOENT silence and non-ENOENT warn (read-only-dir trick in a t.TempDir, or a small removal indirection — mechanic's choice); no arc needed, the ghost-flag reconcile path that bounds the consequence is already arc-adjacent-proven.

This completes the class rulings: top-3 shipped (3d7cf6b22 + 792300943), stale-flag class ruled here, #7-#12 tiers stand as cataloged (bounded/self-retrying and cosmetic tails may be accepted-documented per AC#4's comment rule; #7 cleanStaleMaintenance deserves the SAME loud-warn shape as this class when touched — same consequence genre, maintenance-503 instead of recovery-pass).
---

author: foreman
created: 2026-07-14 20:58
---
STALE-FLAG CLASS COMMITTED — AC#3 DONE (foreman, 2026-07-14 evening): commit 46dbaf36e. Uniform loud-warn per the architect's comment #7 ruling via one shared helper (warnOnStaleFlagRemoveFailure): ENOENT silent (double-removal race unit-tested silent + flock still cleared), any other unlink error → one line with path + raw error + per-site consequence + remedy. Sites: removeUpgradeFlag ×2, ReleaseInstallFlag, resumeNewSb self-heal flag remove, and cleanStaleMaintenance (ranked #7, pre-ruled same shape — its 'Cleaned' line now prints only on confirmed removal, log-honesty per the same principle as the #3 progress-line move; foreman-approved addition). All four markers replaced with ruling-citing comments. Unit tests: nil/ENOENT silent, other-error loud with all three parts present. Mechanic self-caught a doc-comment-attachment repeat of the unit-#2 mistake via go doc before freezing — the lesson stuck. REMAINING ON TICKET: AC#4's accepted-sites half only — ranked #8/#9 (migrate.go ledger DELETEs + full-rollback DROP leftovers, LEDGER DIVERGENCE tier, unruled), #10 (accepted-bounded, needs its ruling-citing comment), #11/#12 (cosmetic tier, accept-documented). One architect pass over the tail closes the ticket.
---

author: architect
created: 2026-07-14 20:59
---
TAIL RULED (architect, 2026-07-14) — closes the catalog. Per tier:

#8/#9 LEDGER DIVERGENCE — FIX NOW, HARD-FAIL. The down-path `DELETE FROM db.migration` and the full-rollback DROP TABLE/SCHEMA are LEDGER WRITES, and the ledger is the ground-truth input to the observed-state direction oracle (MAX(version) feeds Behind/AtTarget — STATBUS-039's machinery). A silently-failed DELETE leaves schema at N−1 with the ledger saying N: a later `migrate up` skips the re-apply, and every observed-state read LIES. Exposure is dev/operator-driven (`./sb migrate down` is not on the autonomous pipeline — rollback restores volumes, never runs migrate down), but a lying ledger on any box poisons everything downstream that reads it. Shape: check runPsql's error at all three sites; on failure RETURN THE ERROR immediately (stopping the down loop — continuing would compound the divergence), wrapped naming the consequence ("schema reverted but the migration ledger still records it as applied — the ledger now lies to migrate up and to observed-state"). Cheap: the surrounding function already returns errors.

#10 recoverFromFlag corrupt-flag + stale-install-flag removes — ACCEPT-BOUNDED, formal. A failed remove re-enters the SAME handling next boot by construction: the corrupt flag is re-read as corrupt and re-removed; no decision is taken on the stale artifact in the meantime, so no lie follows the failure. The existing FLAG_CORRUPT print already names the event. Marker → ruling-citing comment.

#11 backup/log prune RemoveAlls — LOUD-WARN, not silent accept, and history is the argument: jo's box accumulated NINE backup dirs over months precisely because prune failed silently (the "Backup ownership" heal step in the install ladder exists because of it — install.go's own comment records the incident). Same shape as the stale-flag class (46dbaf36e): os.IsNotExist silent; other errors → one loud line with path + error + consequence ("backups/logs accumulate; disk fills over months — the exact pre-heal jo failure") + remedy. Not the siren.

#12 periodic-poll UPDATEs + PostgREST NOTIFYs — ACCEPT-DOCUMENTED, formal. Self-correction is real by construction: the poll re-runs on its own cadence and re-issues the same UPDATE; the reload NOTIFYs are re-sent on the next cycle/config change. No decision reads the outcome in between. Markers → ruling-citing comments.

SUMMARY OF THE WHOLE CATALOG (for AC#4's final sweep): hard-fail — #3 (shipped 792300943), #8/#9 (this ruling); ABORT tier — #2 (shipped 3d7cf6b22); capture-and-fold — #1 (shipped 792300943); loud-warn — #4/#5/#6 (shipped 46dbaf36e), #7 (pre-ruled, shipped 46dbaf36e), #11 (this ruling); accept-documented — #10, #12 (this ruling). Oracle for the closing unit: go test (the migrate-down error paths get unit coverage — a failing runPsql stub returning error must abort the loop) + build/vet; no arc (dev-command surface).
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All fifteen cataloged silently-ignored errors in the upgrade/migrate core are now fixed or formally accepted with ruling-citing comments, across four reviewed units:

- 3d7cf6b22 (ranked #2, highest consequence): compose.VerifyStopped — fail-closed allow-list + bounded re-check before any pre-restore volume rsync; new honest ABORT tier (ROLLBACK_FAILED_SERVICES_NOT_STOPPED / failed-abort-services-live) in rollback(); ReattemptRestore stays reattemptable; structural pin 3→4; timeline doc row.
- 792300943 (ranked #1 + #3): ABORT-branch restoreDatabase outcome folded into the terminal message; CI-not-ready unschedule hard-fails through markPgInvariantTerminal on Exec error or RowsAffected==0.
- 46dbaf36e (stale-flag class, ranked #4-#7): uniform loud-warn via warnOnStaleFlagRemoveFailure — ENOENT silent, every other unlink error names path + error + consequence + remedy; cleanStaleMaintenance included with its maintenance-503 consequence.
- c526c8e81 (tail, ranked #8-#12): migrate-down ledger writes hard-fail and abort the loop (unit-proven via runPsqlFn seam); prune RemoveAlls loud-warn (the nine-backup-dirs incident); #10 accept-bounded and #12 accept-documented with formal comments.

Every fix replaced its STATBUS-176 explicit-ignore marker; the final sweep confirms the only remaining marker in cli/ is a historical note unrelated to the catalog. Architect ruled every tier (comments #1, #3, #5, #7, #9); mechanic executed; foreman line-reviewed and independently verified each unit. Oracles: unit tests (classification table, structural contract, down-loop abort, ENOENT/warn split) + the restore-broke-reattempt arc covering the restore paths on its next natural re-run.
<!-- SECTION:FINAL_SUMMARY:END -->
