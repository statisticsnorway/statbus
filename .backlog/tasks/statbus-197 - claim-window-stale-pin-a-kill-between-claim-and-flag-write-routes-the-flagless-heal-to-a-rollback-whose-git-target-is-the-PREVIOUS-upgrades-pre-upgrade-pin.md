---
id: STATBUS-197
title: >-
  claim-window-stale-pin: a kill between claim and flag-write routes the
  flagless heal to a rollback whose git target is the PREVIOUS upgrade's
  pre-upgrade pin
status: In Progress
assignee: []
created_date: '2026-07-29 11:09'
updated_date: '2026-07-29 11:33'
labels:
  - upgrade
  - recovery
  - triage
  - defect
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/exec.go
priority: low
ordinal: 197000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: recovery never moves a box to a version no one asked for — a restore target must belong to the upgrade being recovered, never to a predecessor's pin.
> FOUND: 2026-07-29, by the architect during STATBUS-195's AC#2 build-time interaction check (kill-mid-discovery-after-claim). Analysis-only — NO observed occurrence; the window is sub-second and needs a watchdog-class kill inside it.
> STAGE: triage — architect disposition ruling (real gap vs guarded-already), then small build if real.

THE WINDOW: executeScheduled's claim (UPDATE scheduled→in_progress + started_at) commits BEFORE executeUpgrade writes the upgrade flag (~sub-second later). A kill inside that window leaves [in_progress row + NO flag + box untouched at the SOURCE version + backup_path NULL + no fresh pre-upgrade pin].

WHAT THE HEAL THEN DOES (byte-walked): next boot → completeInProgressUpgrade finds the orphan row → observed state reads Behind (binary at source ≠ row target) → recoveryRollback. The DB side is SAFE by existing design: restoreDatabase refuses on backupPath == "" ('nothing to restore; refuse to touch the volume; caller records rolled_back' — exec.go:858-874, deliberate). THE OPEN QUESTION is the GIT side: the rollback's restore target is the pinned pre-upgrade branch (STATBUS-077 single source), but THIS attempt never pinned — the standing pin belongs to the PREVIOUS upgrade and points one version BACK. If restoreGitState checks out that stale pin, the box regresses git/binary one version while the DB stays current — the mixed-era class the campaign killed elsewhere (039/026 genre).

TO RULE: (a) read restoreGitState + the recovery-boot checkout gate (STATBUS-061 shipped 'gate the recovery-boot checkout' — it may already refuse this); (b) if unguarded, the fix shape is small: the heal for a never-started row (no flag, backup_path NULL, observed source == current) should mark the row failed/rolled_back WITHOUT any git/binary restore — there is nothing to undo; (c) oracle: Go unit on the disposition seam, or one arc leg only if the window can be hit via the existing inject vocabulary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect disposition: the stale-pin git-restore path for a never-started claimed row is either PROVEN guarded (cite the refusing check) or ruled a real gap with the no-restore fix shape
- [ ] #2 If real: the never-started heal marks the row terminal without touching git/binary/volume; oracle named and green
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-29 11:33
---
DISPOSITION RULING (architect, fresh eyes, 2026-07-29): REAL GAP — and WIDER than filed. Every step below byte-verified today.

THE WINDOWS — there are TWO, both inheriting the predecessor's pin. The `pre-upgrade` branch is pinned at service.go:5521, AFTER the db stop (:5495) and AFTER writeUpgradeFlag (:5327). So: W1 = claim-commit → flag-write (sub-second, the filed scope; heals FLAGLESS via completeInProgressUpgrade) and W2 = flag-write → pin (SECONDS: maintenance on, window engage, db stop all sit inside it; recovers FLAGGED via recoverFromFlag's PreSwap arm). A kill in either leaves the standing pin pointing at the PREVIOUS upgrade's pre-state — one version behind the box.

THE ROUTE (W1, byte-walked): completeInProgressUpgrade → verifyUpgradeObservedStateEx → ObservedCannotReachNew, which is POSITIVELY-verified-behind on plain binary mismatch (service.go:2619) — a box at source vs a row targeting T classifies Behind → recoveryRollback (:3015) with a synthesized flag whose BackupPath = row backup_path = NULL→"".

THE ASYMMETRY (the defect): the DB leg IS identity-guarded — restoreDatabase refuses on backupPath=="" with the exact principle 'the DB was never mutated' (exec.go:870-874). The GIT leg is NOT: d.rollback restores git 'ALWAYS, with no restoreTargetSHA guard' (service.go:8044-8049, deliberate comment) → restoreGitStateFn("") falls back to `git checkout -f pre-upgrade` (:8248-8264, no identity check tying the pin to THIS row) → the box regresses git to R (one version back); restoreBinary then installs ./sb.old — also the predecessor's, = R's binary. Outcome: git+binary at R, DB schema at current S, row marked 'rolled_back' — a mixed-era box (DB one era AHEAD of code) asserting coherence was restored, moved to a version no one asked for. The 039/026 genre, exactly.

SUB-CASE, worse: FIRST-EVER upgrade on a box killed in the window — no pin exists at all → restoreGitStateFn errors (neither ref resolves) → the ABORT branch (service.go:8055+) deliberately STOPS services, prints CATASTROPHIC FAILURE, rows 'failed' — a full outage for a crash that touched nothing.

FIX SHAPE (the no-restore rule, ruled): make the git+binary legs obey the SAME identity key the DB leg already obeys. In the rollback pipeline: backupPath=="" means the attempt died before ANY destructive step (checkout, binary swap, migrations all sit after backup success in executeUpgrade) — there is nothing to undo on ANY axis. Skip restoreGitState + restoreBinary; KEEP the pipeline tail (docker up, reconnect, maintenance off, window lift, terminal write) so the box returns to service at the untouched source and 'rolled_back' lands honestly. ONE guard, in the rollback itself — it covers W1 (flagless heal), W2 (flagged PreSwap recovery), and dissolves the no-pin ABORT sub-case, with no new state and no heal-side special case.

BUILD-TIME OBLIGATION for the implementer: prove there is NO path where git/binary HAVE moved while recorded backupPath is still "" — walk executeUpgrade between backup success and the backup_path record; if such a gap exists, record backup_path before the first destructive step (or refuse). ORACLE (AC#2): RED-first Go unit on the disposition seam — rollback with backupPath=="" must not invoke restoreGitState/restoreBinary (seam or extractFuncBody-order pin, same family as TestRecoveryRollback_ParkedSkipPrecedesRestore); an arc leg only if the window is reachable with a new claim-window KillHere marker (an ADDITION to the King's inject vocabulary — normal, not thinning).

Priority stays LOW (W1 sub-second, W2 seconds, needs a watchdog-class kill inside it; zero observed occurrences). AC#1 checked — ruled real with the fix shape. AC#2 build awaits the King's design nod per standing rule (fix designs run by the King before staging); queued for his one-by-one decision interview.
---
<!-- COMMENTS:END -->
