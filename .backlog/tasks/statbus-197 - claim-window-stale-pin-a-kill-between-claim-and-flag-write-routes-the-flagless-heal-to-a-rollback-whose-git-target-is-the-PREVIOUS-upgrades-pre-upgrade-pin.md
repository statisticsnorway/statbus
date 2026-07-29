---
id: STATBUS-197
title: >-
  claim-window-stale-pin: a kill between claim and flag-write routes the
  flagless heal to a rollback whose git target is the PREVIOUS upgrade's
  pre-upgrade pin
status: To Do
assignee: []
created_date: '2026-07-29 11:09'
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
- [ ] #1 Architect disposition: the stale-pin git-restore path for a never-started claimed row is either PROVEN guarded (cite the refusing check) or ruled a real gap with the no-restore fix shape
- [ ] #2 If real: the never-started heal marks the row terminal without touching git/binary/volume; oracle named and green
<!-- AC:END -->
