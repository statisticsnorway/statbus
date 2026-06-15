---
id: STATBUS-052
title: >-
  install-log-honesty: quiesce confirms upgrade death via the authoritative
  flock, not inference [047 item D]
status: To Do
assignee: []
created_date: '2026-06-15 10:42'
labels:
  - upgrade
  - install
  - install-log-honesty
  - recovery
dependencies: []
references:
  - tmp/architect-047D-pid-liveness.md
  - cli/cmd/install_upgrade.go
  - cli/internal/upgrade/service.go
  - cli/internal/install/state.go
priority: medium
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From STATBUS-047 item D (rune install-log review). Install-log-honesty family — same theme as STATBUS-051 (item C). Architect diagnosis (foreman-verified end-to-end against live code): tmp/architect-047D-pid-liveness.md. All Go control-flow/logging — NO migration.

## Root cause (verified)
The takeover quiesce `stopRestartUpgradeUnit` (cli/cmd/install_upgrade.go:296-323) is the ONE place in the upgrade/recovery machinery that still INFERS whether the killed upgrade process is gone:
- L304 logs "(unit likely already dead)" as a GUESS from the SIGKILL exit status (kill can return non-zero for unit-name miss / dbus error, not only "already dead").
- L306-313 polls the UNIT's systemd MainPID with a SILENT break-on-10s-timeout — never the flock, never the flag PID. On timeout it falls through with NO log and NO distinction between "confirmed MainPID==0" and "still alive after 10s" (inference-by-omission).
- It receives only the `instance` string, so it cannot consult the flock.
This is the rune log's "(unit likely already dead)" line (tmp/no-install.log L56-58).

## The authoritative signal is the flock — PID was already rejected (verified)
- `IsFlockHeld(projDir)` (service.go:699) is a race-free, PID-reuse-immune positive check: non-blocking LOCK_EX on the flag file → held ⇒ live, free ⇒ ghost; kernel-released on holder death (fd teardown). A recycled PID cannot inherit a dead holder's flock — no identity-pairing needed.
- Detect already keys liveness on it: state.go:172 returns `upgrade.IsFlockHeld(projDir)` and DISCARDS ReadFlagFile's pidAlive bool. So the very decision to take over rides on the flock.
- pidAlive was REMOVED as a liveness guard (service.go:784-789): "pidAlive was unreliable: the service survives SHA upgrades, so PID stays alive after the upgrade completes — creating a ghost flag that pidAlive can't detect." service.go:241-244 documents PID/pidAlive as DIAGNOSTIC ONLY.
- recoveryRollback (service.go:2107-2143) acquires the flock before any destructive op and YIELDS if held — the real correctness serializer.
NB this CORRECTS the original item-D brief (which suggested a PID + /proc/signal-0 check): that reintroduces exactly the ghost-flag unreliability + PID-reuse race the codebase already eliminated. Use the flock.

## Severity: honesty/robustness/consistency, NOT corruption
recoveryRollback's flock gate already prevents two concurrent destructive restores regardless of the quiesce's narration. So this is: a dishonest operator-facing log ("(likely already dead)" is a guess); a silent-timeout (a SIGKILL that did NOT take is indistinguishable from a clean kill); and the lone holdout from the flock-authoritative discipline Detect/recoverFromFlag/recoveryRollback all follow.

## Fix (Go control-flow/logging — NO migration)
1. Thread `projDir` into `stopRestartUpgradeUnit` (its caller runCrashRecovery already has it). Read ReadFlagFile(projDir) once for the diagnostic PID/Holder/StartedAt to name WHO.
2. Replace the L304 inference with a factual line: the SIGKILL was sent; liveness is determined by the flock below, not the kill exit status. Keep the kill error as a plain note, not a liveness claim.
3. Confirm death by polling `IsFlockHeld(projDir) == false` (same ≤10s budget). Optionally keep the MainPID poll as corroboration, but the flock is the gate. Explicit outcomes:
   - flock released within the window → log "confirmed dead (flock released) — proceeding" and continue.
   - flock still held at timeout → LOUD, actionable log (the SIGKILL did not release the lock; holder PID N / holder=… may still be alive). DECISION (foreman, North-Star): OBSERVER, not gate — narrate loudly and proceed; recoveryRollback's single flock gate is the authoritative serializer and yields rather than risk a concurrent destructive restore. Do NOT add a second hard-abort gate in the quiesce (one authoritative gate beats two that can disagree; and halting would force operator investigation — anti the unattended-self-heal North Star). Correctness is preserved either way.
4. Do NOT introduce pidAlive(flag.PID) / /proc/<pid> / signal-0 — reintroduces the ghost-flag + PID-reuse hazards the flock is immune to.

## Verify
- Unit test (no systemd needed): a fixture holding a real Flock(LOCK_EX) on a temp upgrade-in-progress.json — assert the quiesce reports "still held" while held and "confirmed dead" once released (mirrors IsFlockHeld semantics).
- Behavioral (install-recovery harness): the crash-loop takeover scenario asserts the new "confirmed dead (flock released)" line appears and the "(likely already dead)" guess is gone.
- go -C cli vet/build/test green.
- do-not-self-commit: report to foreman with the diff + test for byte-level review + commit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 stopRestartUpgradeUnit confirms upgrade death by polling IsFlockHeld(projDir)==false (the authoritative, PID-reuse-immune signal Detect + recoveryRollback already use), with projDir threaded in from runCrashRecovery; the flag PID/Holder is kept only as the diagnostic WHO
- [ ] #2 The L304 '(unit likely already dead)' inference and the silent break-on-timeout are gone: the SIGKILL is logged as sent (liveness NOT claimed from its exit status); outcomes are explicit — flock released → 'confirmed dead (flock released) — proceeding'; still-held@timeout → loud actionable log
- [ ] #3 Still-held-at-timeout is OBSERVER, not gate: the quiesce narrates loudly and proceeds; recoveryRollback's flock gate remains the single authoritative serializer (no second hard-abort gate added). NO pidAlive/proc/signal-0 check introduced
- [ ] #4 Unit test with a real Flock fixture (held → 'still held'; released → 'confirmed dead'); go vet/build/test green
- [ ] #5 NO migration; foreman byte-level reviewed + committed (do-not-self-commit)
<!-- AC:END -->
