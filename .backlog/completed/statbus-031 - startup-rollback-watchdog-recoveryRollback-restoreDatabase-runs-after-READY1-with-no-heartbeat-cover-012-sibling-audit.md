---
id: STATBUS-031
title: >-
  startup-rollback-watchdog: rollback-restore-watchdog test needs real-VM timing
  tuning (heartbeat coverage on the rollback path)
status: Done
assignee:
  - architect
created_date: '2026-06-11 13:39'
updated_date: '2026-06-21 20:04'
labels:
  - upgrade
  - recovery
  - product
  - audit
dependencies: []
references:
  - STATBUS-039
documentation:
  - >-
    doc-007 -
    Roadmap-completing-install-upgrade-robustness-—-Norway-rollout-then-external-standalone.md
priority: high
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CONFIRMED (architect sweep, 2026-06-11 — supersedes the original "suspected" framing). The LAST uncovered DB-size-scaled step in service startup; wedge list is bounded: 017 done, 012 done, 031 last. KING DECISION at the rc.01 cut: this gates the STABLE/Norway promotion, not the prerelease.

THE GAP: restoreDatabase (exec.go:695-714) restores the DB volume via a docker-run rsync of the WHOLE volume — onAdvance=nil, output to progress.File() which bypasses the heartbeat; the last WATCHDOG=1 ping is one progress.Write BEFORE the rsync (exec.go:703). Startup path (recoverFromFlag service.go:1720 → recoveryRollback :2135 → rollback :4649 → restoreDatabase :4777) has ZERO ticker → watchdog kills ~120s into the restore. Execute path (postSwapFailure :3675 → rollback, gated ticker still armed) closes its gate after 3 min of rsync silence (watchdog.go:134) → killed too. The flag is removed only AFTER the restore completes, so a mid-restore kill → next boot → restore FROM SCRATCH → killed again = indefinite restore loop (the rune-wedge shape) on the recovery path itself. Norway 32 GB: a >120s restore is essentially guaranteed.

FOUR startup entries funnel into the same chokepoint: the Resuming/PreSwap latch (:762/:829), recoverFromFlag ground-truth failures (:889/:908/:922/:1042), completeInProgressUpgrade ground-truth failure (:2271), resumePostSwap stale-flag binary-skew. One fix covers all.

THE FIX: an always-ping watchdog ticker (runGatedWatchdogTicker, nil progress — the exact 012 primitive) wrapping the BODY of rollback() — covers the restore AND the equally-silent rollback-docker-up (5m, onAdvance=nil); raise the 10-min rsync timeout (exec.go:704) to a shared generous constant (the MigrateUpTimeout=30m philosophy); repair the comments in the same commit; add a source-order guard test (TestBootMigrateWatchdogCover_SourceOrder style).

THE PROOF: the 012 protocol — RED scenario (stall/slow the restore during startup recovery) on unfixed code → King ratifies → fix → GREEN. ~2 VM-hours, ~€0.015.

ALSO CLEARED BY THE SWEEP (no work, recorded for honesty): every other step from process start to the first main-loop heartbeat is covered or bounded. Three LOW non-wedge liveness nits (initial-discover network blackhole ≤5m cap; wedged-dockerd resume probes ≤2m caps; pruneBackups RemoveAll on a rare path) — environmental, self-healing, no destructive rework; fix only if the King asks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 King ratifies the fix design in this description (ticker wrap at rollback(), shared restore timeout, comments, guard test)
- [ ] #2 RED observed on a real VM: restore stalled during startup recovery → watchdog kill on unfixed code (NRestarts delta ≥1 from post-stall baseline / Result=watchdog)
- [x] #3 Fix landed: always-ping ticker wraps rollback(); restore timeout raised to the shared constant; comments repaired; source-order guard test added
- [ ] #4 GREEN on a real VM: same stall, NRestarts delta=0, rollback completes, data intact, flag absent
- [ ] #5 RED→GREEN pair recorded here with run IDs/VM names
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design + sweep ledger deep-reference: STATBUS-036 (campaign roadmap, Track A1/A2). Self-sufficient. Status: 031's remaining work = the always-ping watchdog ticker wrapping rollback() (the 012 pattern); awaiting King ratification, then RED→fix→GREEN.

COUPLING — REFRAMED + GUARD SHIPPED (King correction 2026-06-12, post-039-commit). The original note framed this as "without 031's guard, rune suffers a silent ~2.5-week data loss." The King refuted that premise: a wedged box locks browser users out via the app's upgrade guard, so rune accumulated ZERO domain writes in 18 days — an unusable installation, not data loss. The REAL justification for the identity guard (verified in-repo): the restore path's pickLatestBackup restored the LATEST backup, not the recovered upgrade's OWN snapshot, during the aside-rename window — a genuine silent-wrong-restore for any box that DOES have data, completing silently under install today. STATBUS-039 (commit 5eacd6305) SHIPPED the fix: identity-keyed restore (consume only flag.BackupPath / row.backup_path; empty→refuse, missing→fail-loud; pickLatestBackup deleted). The guard precondition is now MET. 031's watchdog ticker can land safely on top — with identity-keying in, every restore is the upgrade's own snapshot, so a watchdog-covered (completing) restore is correct, never a silent-loss amplifier. 031 is no longer blocked by the guard.

KING RATIFIED + DISPATCHED 2026-06-15 ('that needs fixing' = AC#1). Foreman re-VERIFIED the gap is STILL OPEN against current master: runGatedWatchdogTicker is called ONLY at boot-migrate (service.go:1582) + applyPostSwap (service.go:4104); rollback() (service.go:4997) → restoreDatabase has NO ticker. So a large-DB rollback restore on the startup recovery path has zero heartbeat → killed mid-restore → loop. (039's identity-keyed restore is in — the guard precondition is MET, so the ticker can land safely.) Architect implementing the always-ping ticker wrap of rollback() + the shared restore timeout + the source-order guard test, then RED→fix→GREEN on a VM (operator drives). do-not-self-commit → foreman reviews+commits.

ARCHITECT IMPLEMENTATION (2026-06-15, Opus 4.8) — staged, NOT committed (foreman byte-level review+commit). go build/vet green; affected pkgs (internal/upgrade + internal/inject) test green incl. the new guard; full cli suite running. 5 files staged: service.go, exec.go, watchdog.go, inject.go, + new rollback_watchdog_cover_test.go. (NB two OTHER files show modified-but-unstaged — .github/workflows/install-recovery-harness.yaml + test/install-recovery/run.sh — NOT mine; left untouched.)

CODE (AC#3):
1. rollback() (service.go) body wrapped in the always-ping watchdog ticker — `go runGatedWatchdogTicker(rollbackTickerCtx, nil, applyPostSwapStallThreshold, applyPostSwapWatchdogCadence, sdNotify-WATCHDOG, done)` armed at the TOP, deferred cancel+join. nil progress = ping unconditionally (the proven 012 primitive); covers restoreDatabase's silent rsync AND the silent rollback-docker-up, for ALL FOUR startup entries that funnel through rollback(). Note: rollback() always exits via os.Exit (ABORT=1 / terminal=75) so the goroutine is reaped by process death (watchdog fed right to exit); the defer is insurance for any future early-return path.
2. restoreDatabase rsync timeout 10m → shared `RestoreDBTimeout = 30m` (exec.go), MigrateUpTimeout philosophy. The always-ping cover suppresses the 120s WatchdogSec false-kill, so this ceiling is the real hang-bound.
3. Comments repaired: restoreDatabase doc (now notes the rollback() cover); runGatedWatchdogTicker doc (was 'applyPostSwap's SINGLE' → now names all 3 callers: boot-migrate, applyPostSwap, rollback).
4. Source-order guard test: TestRollbackWatchdogCover_SourceOrder (rollback_watchdog_cover_test.go) — asserts the nil-progress ticker arms BEFORE restoreDatabase + the docker-up, cancel+join present, and restoreDatabase uses the shared RestoreDBTimeout (no 10m literal).
5. RED injection point: `inject.StallHere("restore-db-stall-watchdog")` added inside restoreDatabase (before the rsync); registered KindStall in inject.go (Validate-known). No-op in production.

NO migration.

RED→GREEN VM SCENARIO SPEC (012 protocol) — for the operator to implement/run, foreman to sequence (~2 VM-hrs):

NEW scenario `test/install-recovery/scenarios/4-rollback-restore-watchdog.sh`. Clone the SHAPE of 3-postswap-archivebackup-watchdog.sh (the silent-step → WatchdogSec → NRestarts assertion harness) but with the rollback-path TRIGGER of 3-postswap-resume-died-rollback.sh (drive a STARTUP-recovery rollback: a flag whose ground-truth verdict is POSITIVELY-behind → recoverFromFlag → recoveryRollback → rollback → restoreDatabase — STATBUS-039 at-target/unverifiable verdicts retry FORWARD and never reach rollback, so the resume-died-rollback driver is the one that lands on restoreDatabase).
ENVELOPE (systemd drop-in env on the upgrade unit): STATBUS_INJECT_AT=restore-db-stall-watchdog ; STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=<vm path> ; STALL_HOLD_S=180 (> WatchdogSec=120). Populate demo data first so the data-intact assertion has counts. Hold the stall, observe, then remove the release file → restore proceeds → rollback completes.
RED build = the staged fix WITH the rollback() ticker block reverted (delete only the 4 lines: rollbackTickerCtx/Done decls + `go runGatedWatchdogTicker(...)` + the `defer func(){cancel(); <-done}()`), KEEPING the StallHere + registry + RestoreDBTimeout. → restoreDatabase parks SILENT 180s on the startup path with no ticker → WatchdogSec fires → SIGABRT → NRestarts delta ≥1 / Result=watchdog → next boot re-restores from scratch → loop. Assert: NRestarts delta ≥1, rollback NOT completed, flag still present.
GREEN build = the full staged fix. → the always-ping ticker fires WATCHDOG=1 every cadence through the 180s stall → unit stays active → remove release file → restore completes → assert NRestarts delta=0, rollback row terminal (rolled_back/failed per outcome), flag ABSENT, data counts intact.
Record the RED+GREEN run IDs/VM names in AC#2/#4/#5. (I can write the full scenario .sh if you'd rather I do it than the operator — say the word; I scoped it as operator/harness work to avoid burning paid-VM cycles debugging a blind 400-line clone.)

AC#3 LANDED — commit a8279ed83 (pushed to master). Foreman byte-level review + independent re-verify all green: (1) shouldPingWatchdog(nil)==true confirmed at progress.go:305 — nil progress pings unconditionally; (2) the rollback ticker call is byte-identical to the proven boot-migrate site (same constants, nil progress, same ping closure) — the deferred-vs-inline cancel difference is CORRECT (rollback always os.Exits, so a defer can't leak the ticker the way it would in Run()'s main loop); (3) fail-loud preserved — dbRestoreErr -> degraded -> state='failed' at service.go:5231/5238, so a 30m-timed-out restore surfaces degraded, never a silent rolled_back; (4) inject imported + precedented (exec.go:20/1013); (5) go build + vet + full targeted cli suite (upgrade, inject, cmd, config) green, re-run independently. 5 files / +145 -6. REMAINING: AC#2/#4/#5 = the VM RED->GREEN proof. Architect writing the new scenario 4-rollback-restore-watchdog.sh (it owns the spec + minimizes paid-VM waste); then foreman creates the RED branch (master minus the ticker block) + operator drives RED (red branch) -> GREEN (master).

PROOF PAIR PREPPED (foreman, 2026-06-15). Scenario 4-rollback-restore-watchdog.sh reviewed + COMMITTED to master d6cafcdf7 (GREEN SHA). RED branch cut: red/031-rollback-watchdog @ 79375b9f9 = GREEN minus exactly the rollback() ticker block (architect's specified delta), replaced with a DO-NOT-MERGE marker; compiles (go build OK); retains StallHere + RestoreDBTimeout + the scenario. Cut in an isolated git worktree (the backlog-MCP auto-commit was confirmed as the index-reset culprit the architect hit 3x — it git-add+commits .backlog and unstages agents' files; pathspec commits + worktree isolation are the defense). Scenario design verified sound: deterministic Resuming-latch trigger (resumePostSwap stamps Phase=Resuming -> death -> recoverFromFlag rolls back, vs the non-deterministic forward-fail path); fail-fast preconditions (backup_path present, Phase=Resuming observed); NRestarts-watch discriminator; baseline-pollution preempted by the 3600s RUN2 RestartSec. Architect flagged it needs VM knob-tuning (STALL_HOLD_S / RestartSec windows / INSTALL_VERSION delta). NEXT (AC#2/#4/#5): operator runs RED (--ref red/031-rollback-watchdog) -> expect NRestarts climb/fail; then GREEN (--ref master) -> expect survive/pass; both -f scenarios=4-rollback-restore-watchdog, SERIALIZED after the 025 smoke (cross-run cleanup-sweep collision). Tune + re-run if a knob trips instead of the watchdog signal.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-06-21 19:33
---
▶ CROSS-REF 2026-06-21 (per architect; pending King's fold call): VM-proof MOVED to 071/5c-hard (the 4-rollback-restore-watchdog scenario re-scoped from the death-during-resume / Resuming-latch trigger to a V_fail trigger — the old trigger is defeated by the STATBUS-067 self-heal at resumePostSwap :5053). PRODUCT CODE already landed: the rollback() always-ping watchdog ticker @ a8279ed83 (pushed). 031's remaining AC#2/#4/#5 (the VM RED→GREEN proof) are now satisfied by 5c-hard's VM-prove. NOTE: the existing RED branch red/031-rollback-watchdog@79375b9f9 is STALE (cut to RED the OLD trigger) — it will be re-cut off current master for the V_fail path at VM-prove time. ARCHITECT LEAN: fold 031→071 (same shape as 091/075/061); awaiting King's call (031 is in his review queue). Keeping both tickets honest until then.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSED — subsumed by STATBUS-071 (King-directed clarity fold, 2026-06-21).

The rollback heartbeat: CODE SHIPPED at a8279ed83 — the always-ping watchdog ticker (runGatedWatchdogTicker, nil progress) wrapping rollback()'s body, so a slow large-DB restore on the recovery path keeps WATCHDOG=1 from a goroutine and isn't SIGABRT'd into a restart loop. AC#1 (King-ratified design) + AC#3 (landed code + source-order guard test TestRollbackWatchdogCover_SourceOrder) are DONE.

The empirical VM RED→GREEN proof (AC#2/#4/#5) MOVED to 071's rollback-restore arc (arcs/postswap-rollback-restore-watchdog-arc.sh): GREEN (master, ticker present) = NRestarts flat at baseline+1 after the t+44s exit-42 handoff + reaches rolled_back + data intact; RED (master-minus-rollback()-ticker, the 79375b9f9 delta re-cut off current master) = SIGABRT climb. The arc finishes observational→asserting after a VM observe grounds the terminal (the arc header flags rolled_back as "never cleanly seen" — never assert an unobserved terminal).

The broken standalone scenario (scenarios/4-rollback-restore-watchdog.sh, death-during-resume trigger now self-heal-blocked by STATBUS-067, and the install-recovery harness can't build a V_fail image) was RETIRED at 41a800994 (+ README catalog cleanup 641563563). Two product-code comments still naming it (inject.go:244, exec.go:760) are deferred to the 071 Phase-2 arc-hardening commit.

Substance + remaining proof live in STATBUS-071 §5c-hard.
<!-- SECTION:FINAL_SUMMARY:END -->
