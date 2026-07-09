---
id: STATBUS-111
title: >-
  recovery-ux: `./sb install` re-attempts a broken restore + recovery
  legend/forecast
status: In Progress
assignee:
  - engineer
created_date: '2026-06-28 12:53'
updated_date: '2026-07-09 00:47'
labels:
  - upgrade
  - recovery
  - operator-ux
dependencies:
  - STATBUS-109
  - STATBUS-110
references:
  - .backlog/docs/doc-019 - Recovery-decision-model-—-the-complete-picture.md
  - doc/upgrade-vocabulary.md
  - tmp/mechanic-restore-broke.md
  - cli/internal/upgrade/service.go
  - cli/internal/install/state.go
  - cli/internal/upgrade/exec.go
  - STATBUS-071
ordinal: 111000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: "./sb install" is the operator's single trained action and must never be a dead end.
> BENEFIT: the one command we tell a stranded operator to run actually re-attempts a broken restore (today it dead-ends at the idempotent step-table on the common failed path), and every terminal tells them what happens next — the difference between self-service recovery in Senegal and a flight.
> STAGE: Stage 1 → Stage 3 (the last recovery-core unit; now unblocked since 046 closed).
> COMPLEXITY: engineer-substantial (install-ladder re-attempt arm + legend/forecast output + the PID/pidAlive removal per the King's flock ruling); architect reviews; arc-proven.
> DEPENDS ON: STATBUS-109, STATBUS-110 (recorded sequence 110→109→046→111; their code is landed — the remaining coupling is arc-lane scheduling on STATBUS-071).

---

## Why
Finalising the recovery operator-UX (STATBUS-107/109). The King's model: `./sb install` is the operator's SINGLE trained action — "if anything's off, run it again." This must hold at the worst moment (a degraded box in a remote office).

VERIFIED GAP (mechanic-grounded, foreman-verified; tmp/mechanic-restore-broke.md): on the COMMON restore-broke path the failed-state message tells the operator "manual CLI recovery is required (./sb install)" — but `./sb install` on that state CANNOT re-attempt the restore. The one action we tell the operator to take is a DEAD END exactly when the box is degraded.

## Grounded current behavior (file:line)
- Two failed-terminal writes set `state='failed'`, exit non-zero, point at `./sb install`: git-restore fail (service.go:5524, exit 1); db-snapshot-restore fail (service.go:5625→5704, exit 75). SQL (5586/5724) sets `state='failed', error`; does NOT touch `backup_path` (retained from 4169/4650).
- Flag removal is CONDITIONAL (5585-5588 / 5723-5726): terminal write LANDS (common — DB reachable) → flag REMOVED; terminal write FAILS (compound — DB volume corrupt) → flag KEPT.
- Install ladder (state.go): flag REMOVED → no CrashedUpgrade probe → DB reachable → no scheduled row → StateNothingScheduled (156) → idempotent step-table, NO restore re-attempt (THE DEAD END). Flag KEPT (compound) → StateCrashedUpgrade (125) → RecoverFromFlag → restore RE-ATTEMPTED (already works).
- restoreDatabase (exec.go:763) = `rsync -a --delete` from a `:ro` source → idempotent / replayable; snapshot can't be corrupted.

## Decision (architect rec — King ratified the direction 2026-06-28)
Option (b): teach the install ladder that a `state='failed'` row WITH a retained `backup_path` (= restore-broke) is RE-ATTEMPTABLE → replay the restore (stop db → restoreDatabase → restart), HUMAN-initiated via `./sb install`.
- Rejected (a) keep-the-flag-on-failed: would make the systemd SERVICE auto-re-attempt on restart → thrash a human-stop. restore-broke must be human-gated.
- Rejected (c) dedicated replay-restore CLI: a bespoke command breaks the "one trained action = ./sb install" model.

## Operator legend + forecast
At recovery-in-progress and at the terminals, print: where-you-are · what-you-can-do (LEGEND: `./sb install` [headline] + state-relevant commands) · what-will-happen (FORECAST = the install entrypoint announcing the detected state + planned action). Headline always `./sb install`; legend shows only state-relevant commands.

At the `rolled_back` terminal the forecast guides the operator FORWARD, TAILORED to why it rolled back (never send them in a circle):
- HARD / persistent error (a real bug; the version repeats the failure) → "rolled back to <old>, healthy. <new> failed: <error>. Report it (log retained at <path>); try a LATER release when available — it may carry the fix. The same version will fail the same way." (Do NOT suggest re-scheduling the same version — `./sb upgrade check` to find a newer one.)
- EXHAUSTED transient (DB/network didn't clear; not the version's fault) → "retry when the environment is healthy — the same version is fine."

## Must be arc-tested
Safety-critical recovery path; prove via the install-recovery arcs (STATBUS-071): kill the restore on the common path → operator runs `./sb install` → restore re-attempted → box recovers. The test run is the only oracle.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On the common restore-broke path (flag removed, state='failed', backup_path retained), re-running `./sb install` RE-ATTEMPTS the snapshot restore (does not dead-end at the idempotent step-table) — proven by an install-recovery arc
- [x] #2 The re-attempt is HUMAN-gated: the systemd service does NOT auto-re-attempt a restore-broke terminal on restart (no auto-thrash to StartLimit)
- [x] #3 The failed-state message + the recovery-in-progress output show a state-relevant command LEGEND + a plain FORECAST; the headline action is always `./sb install`
- [x] #4 At the rolled_back terminal the output suggests the forward path TAILORED to cause — hard/persistent-error rollback → report + try a LATER release (not re-schedule the same version); exhausted-transient rollback → retry-when-healthy
- [ ] #5 restoreDatabase replay is idempotent and verified safe to re-run from the retained snapshot (arc-proven)
- [x] #6 Liveness relies SOLELY on the flock; the stored PID + `pidAlive()` are removed (no load-bearing PID use remains); the live-upgrade refusal (and any operator message needing the holder) emits the hint `lsof tmp/upgrade-in-progress.json`
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PID / LIVENESS DECISION (King, 2026-06-28): liveness = the FLOCK ALONE. DROP the stored PID field + `pidAlive()` (today diagnostic-only, service.go ~:244-247). Rationale: a stored PID is a footgun — after a crash the OS can REUSE that number for an unrelated process, so a `pidAlive()` check can read a stranger as 'still running' → recovery wrongly refuses → box stuck. The flock has no such hole (OS frees it on holder death, reused PID or not). Instead of storing the holder, OUTPUT the hint `lsof tmp/upgrade-in-progress.json` in operator messages WHEN APPROPRIATE — primarily the live-upgrade refusal ('an upgrade is already running' → here's how to see which process). Composable: give the operator the command, don't bake the PID into the file. Code pass: grep + remove all PID/pidAlive uses; confirm none load-bearing.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-09 00:47
---
CODE SHIPPED in 7c86b383e (dual-reviewed: architect ship-with-one-change — the git-first guard — applied; foreman first-hand; built by engineer in checkpointed passes). AC#2/#3/#4/#6 checked: re-attempt is ladder-only + human-gated (service RecoverFromFlag inert on the removed flag); legend/forecast at recovery-in-progress and all terminals with ./sb install as the headline; rolled_back forward path cause-tailored (hard-by-construction — invariant comment at the write site); flock-only liveness with PID + pidAlive removed everywhere and the lsof hint in holder-needing messages. KEY STRUCTURE: rollback()'s restore tail extracted to restoreAndFinalize (line-structural splice; purity machine-checked by the updated structural tests scanning the combined path; no process-lifecycle in the helper — exits stay at rollback()'s ABORT/terminal); ReattemptRestore = watchdog + restoreGitState FIRST (the review's catch: an abort row with a still-corrupt tree hard-fails actionably BEFORE any destructive step — never a mixed-era box; pair-terminal rows no-op through) + db stop + shared restoreAndFinalize; success marks rolled_back. Probe QueryReattemptableRestore (state='failed' AND backup_path IS NOT NULL) proven co-extensive with the three restore-broke terminals via the backup_path⟹post-swap⟹flag-held invariant, enumeration in its comment. CORRECTED ANCHORS: restoreAndFinalize service.go ~6678; rollback() 6856-7044 (exits @6843/@7044); rolled_back+PIN3 ~6829; ladder state.go StateRestoreReattemptable @50 / Detect @169; dispatch install_upgrade.go @40 / runInlineRestoreReattempt @98. OPEN: AC#1/#5 arc-proof — the restore-broke re-attempt arc rides a later wave and MUST exercise BOTH row classes: (a) pair-terminal re-attempt → restore completes → rolled_back; (b) abort-row re-attempt with still-corrupt git → hard-fails actionably (ErrRollbackGitCorrupt), never mixed-era.
---
<!-- COMMENTS:END -->
