---
id: STATBUS-180
title: >-
  daemon-restart-race: crash-recovery restarts the upgrade daemon while the same
  dispatch's restore re-attempt tears down the DB
status: To Do
assignee: []
created_date: '2026-07-14 13:05'
updated_date: '2026-07-14 17:57'
labels:
  - upgrade
  - install-recovery
  - timing
  - low-severity
dependencies: []
priority: low
ordinal: 181000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: no product actor briefly fails by design — two independent actors inside one `./sb install` dispatch should not race each other's containers.
> FOUND: 2026-07-14, restore-broke-reattempt arc run 29325230294 (mechanic diagnosis, log-grounded): runCrashRecovery (install_upgrade.go ~:506) explicitly `systemctl --user start`s the quiesced upgrade daemon right after the pair-terminal write lands — in the SAME window where the SAME dispatch's re-attempt (StateRestoreReattemptable) is stopping/restoring the DB containers. The freshly-started daemon's boot-migrate check hits the DB mid-teardown, fails ("query applied migrations: exit status 2" / "boot migrate up: exit status 1"), unit exits 1, systemd Restart=always retries 30s later and comes up clean (restore complete by then).
> SEVERITY: benign and self-healing (one restart-counter tick, no data effect, no wedge) — but it is a real timing window between two independent product actors, and it costs an NRestarts tick + a FAILURE line in the journal that an operator/diagnostic tool could misread.

CANDIDATE FIX (mechanic's suggestion, unruled): delay the crash-recovery daemon restart until after any same-dispatch re-attempt concludes — i.e. the dispatch's terminal actions ordering becomes: pair-terminal write → re-detect → (re-attempt if matched) → THEN daemon start. Needs an architect look at whether the daemon start has other dependents expecting it earlier.

EVIDENCE: run 29325230294 log 10:41:23 window; the arc's NRestarts bound (2) deliberately tolerates the tick, with a comment pointing here.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect rules the fix shape (reorder daemon start vs re-attempt, or accept-and-document)
- [ ] #2 If reordered: the restore-broke-reattempt arc's NRestarts bound tightens back and the journal shows no FAILURE line in the window — proven by the arc run
- [ ] #3 If accepted: the window is documented at runCrashRecovery's start call with a pointer to this ticket
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-14 13:14
---
RULING (architect, 2026-07-14) — AC#1: REORDER, not accept-and-document. Specifically: hoist the restart-closure invocation from runCrashRecovery's own defer to the install DISPATCH LADDER's conclusion.

GROUNDING (verified): the daemon restart is already a CLOSURE — stopRestartUpgradeUnit returns `restartIfEnabled func()` and runCrashRecovery fires it in a `recovered`-gated defer (cli/cmd/install_upgrade.go:202-213). The defer fires when runCrashRecovery RETURNS — before the ladder re-detects and dispatches the same-dispatch re-attempt (StateRestoreReattemptable → ReattemptRestore at :114), whose pre-restore stop (`docker compose stop app worker rest db`, service.go:7383) is exactly what the fresh daemon's boot-migrate then hits. The race is a plumbing artifact of WHERE the closure fires, not a missing mechanism.

THE SHAPE:
1. runCrashRecovery no longer invokes the closure; on recovered=true it HANDS IT UP to the dispatch owner (return value or out-param — builder's choice).
2. The install ladder invokes it DEFERRED at dispatch conclusion, so EVERY dispatch exit path fires it — including a failed re-attempt. A degraded (failed-row) box must still get its daemon back: that daemon is how the box receives the fix release (schedule → notify → the table is the queue). Leaving it stopped on re-attempt failure would strand the box silently — worse than the tick we are removing.
3. PRESERVED semantics, unchanged: recovered=false → unit stays stopped (a failed recovery must not resurrect the crash loop — the existing comment's rationale); wasEnabled=false → the no-op closure (operator had it disabled; respect that).
4. No dependents expect the earlier start (the ticket's open question): ReattemptRestore is install-driven with its own connection; a scheduled-upgrade re-dispatch runs INLINE and is strictly safer with the daemon down (no claim race against a booting daemon). Nothing in the ladder needs the unit up mid-dispatch.

WHY REORDER OVER ACCEPT: (a) the North Star — no product actor fails by design; (b) the FAILURE journal line + NRestarts tick land in exactly the window convergence observation (170) reads — designed-in noise on the surface we just made trustworthy; (c) the fix is plumbing an existing closure, no new machinery, and the arc that proves it already exists.

ORACLE (AC#2 as written): re-run the restore-broke-reattempt arc — the NRestarts bound tightens back (remove the tolerance + its pointer comment here), and the journal shows no FAILURE line in the window. AC#3 lapses (not the accept path).

ADJACENT FINDING, out of this ticket's scope (reported to foreman for a separate call): the same run's recovery_attempts 3→0 "reset" is the volume restore itself — restoreAndFinalize → restoreDatabase (service.go:7133) physically rewinds public.upgrade to backup-time values and writeRollbackTerminal (service.go:7078) re-imposes only the terminal columns. No SQL reset exists; details with the foreman.
---

author: architect
created: 2026-07-14 17:57
---
SAFETY-CORE PASS (architect, 2026-07-14): SHIP with ONE comment-line amendment. All four pressure points resolved:

(1) CALLERS: exactly one call site (install.go:414), passes &restartIfRecovered; no nil-passing caller exists (root.go/service.go hits are comments). The signature's nil-tolerance is dead-defensive but documented and harmless.
(2) DEFER PLACEMENT: registration sits inside the StateCrashedUpgrade branch immediately BEFORE the only runCrashRecovery call — no path can run recovery without registering first; the defer is runInstall-scoped, covering re-detect, re-attempt, and every error return. THE ONE AMENDMENT (A1, comment-only): the install.go comment says "covering every exit path below" — not exactly true: the inline scheduled-upgrade dispatch's syscall.Exec handoff (install_upgrade.go:228 genre) REPLACES the process and skips defers, losing the closure. That loss is compensated — the inline upgrade restarts the unit itself at completion (the documented contract), a mid-exec crash leaves the flag so the next install hands up again, and the daemon staying down through the inline dispatch is the ruling's own claim-race avoidance — so behavior is equal-or-better than pre-180 on that path. But the comment must SAY it ("except a syscall.Exec handoff, which skips defers; the exec'd continuation owns the unit restart") — safety-core comments must be exactly true.
(3) HAND-UP ATOMICITY: the out-param is assigned in runCrashRecovery's own defer keyed on `recovered`, which settles at exactly two sites (:400 the STATBUS-147 re-parked-error case — verified it sets recovered=true then returns the error, the ruling's named case; :405 success). The closure is fully built at function head before any fallible work; a mid-recovery panic leaves recovered=false → nothing assigned → the caller's nil-check skips. No half-built fire is possible.
(4) NRestarts 0 IS HONEST: the replaced arc comment itself documented phase (i)'s raced restart as the ONLY remaining contributor and phase (ii) as zero (every dispatch runs ./sb install over SSH with the daemon stopped; kills hit the install process, not the supervised unit). The new negative journal asserts use the raced run's exact error substrings — AC#2's second half done properly. Nit, acceptable: the journal grep passes silently if journalctl itself fails (empty input) — the sibling asserts prove the unit ran, so the direction is safe.

After A1: commit; the arc re-run is AC#2's oracle as ruled.
---
<!-- COMMENTS:END -->
