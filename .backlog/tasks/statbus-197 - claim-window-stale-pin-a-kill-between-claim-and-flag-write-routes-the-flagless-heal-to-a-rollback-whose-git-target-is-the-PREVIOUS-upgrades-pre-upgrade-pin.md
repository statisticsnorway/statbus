---
id: STATBUS-197
title: >-
  claim-window-stale-pin: a kill between claim and flag-write routes the
  flagless heal to a rollback whose git target is the PREVIOUS upgrade's
  pre-upgrade pin
status: In Progress
assignee: []
created_date: '2026-07-29 11:09'
updated_date: '2026-08-02 15:32'
labels:
  - upgrade
  - recovery
  - triage
  - defect
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/exec.go
priority: medium
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
- [ ] #3 Restore identity is recorded ONLY at snapshot commit: the pre-commit row backup_path write is gone; row AND flag BackupPath are both stamped right after backupDatabase returns (phase unchanged); source-order pinned by a Go unit
- [ ] #4 ./sb.old is deleted at serve-proven completion, so sb.old-exists ⇔ an unresolved swap; pinned by a Go unit
- [ ] #5 The three preswap arcs stay green on the changed geometry: preswap-backup-kill (empty-path refusal arm), preswap-checkout-kill (full-restore arm, data intact), preswap-binary-swap-kill (binary restored from THIS attempt's sb.old)
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

author: architect
created: 2026-08-02 15:32
---
BUILD SPECIFICATION (architect, 2026-08-02; supersedes comment #1's build sketch — the King asked for a whispers-proof brief; every line below byte-verified today. THREE new findings from discharging comment #1's build-time obligation changed the shape; the fix is now a small FOUNDATION, not a one-line guard).

THE INVARIANT (state it once, build everything from it): recovery restores exactly what THIS attempt touched — the DB only from this attempt's committed snapshot, git only to this attempt's own pin, the binary only from this attempt's own swap. If the attempt touched nothing, restore nothing and land rolled_back honestly, with services up.

FINDINGS THAT RESHAPED THE FIX (deltas vs comment #1):
F1. Comment #1's premise 'backup_path is recorded after backup success' is WRONG. The row's backup_path is recorded EARLY as intent — service.go:5428, before the read-only window, maintenance, db stop (:5495), pin (:5521), and the snapshot itself (:5529). This violates the code's own written contract at exec.go:423-426 ('Only a COMMITTED path is ever recorded on the flag/row'). Consequence: W2 is minutes-wide (the image pull sits inside flag→pin), and a flag-lost heal in [record→snapshot-start] would restore the PREVIOUS upgrade's pre-upgrade-active snapshot — weeks of data regression. Producers are weak (no flag rewrite in that span; repo-local tmp/ survives reboot) but the class is real.
F2. flag.BackupPath is stamped only at :5654, AFTER checkout and the binary swap (:5628). So a kill during checkout/swap leaves flag.BackupPath=="" while git/binary HAVE moved — comment #1's naive guard would skip restores that are genuinely needed there.
F3. ./sb.old is NEVER deleted on completion (:8327 'kept as rollback'). On any box past its first upgrade, a rollback reaching restoreBinary without this attempt having swapped installs the PREVIOUS upgrade's old binary. (The green preswap arcs never caught this — they run on a box's FIRST upgrade, where no stale sb.old exists.) selfupdate.Rollback consumes sb.old on the rollback path; only COMPLETION leaves it stale.

THE CHANGES (each small, each with its oracle):
C1. RECORD IDENTITY AT COMMIT, NOWHERE ELSE. Delete the early row UPDATE at service.go:5428 (its only stated value, reconcile correlation, keeps the on-disk-stamp fallback per its own comment :5432). Immediately after backupDatabase returns (:5529): (a) UPDATE row backup_path, (b) rewrite the flag with BackupPath=path via a new tiny helper mirroring updateFlagNewSbSwapped (:550) — Phase UNCHANGED (old-sb-upgrading). The :5654 swap stamp keeps carrying it unchanged. After C1: path-empty ⇔ died before commit ⇔ checkout/swap/migrations unreached ⇔ nothing moved, TRUE in every carrier (row, flag, synthesized flag).
C2. THE NO-TOUCH GUARD in d.rollback, immediately before the git leg (:8044 region): if backupPath=="" → skip restoreGitState AND restoreBinary (the DB leg already refuses, exec.go:870-874); progress.Write the principle ('this attempt touched nothing — refusing to restore git/binary from state that may predate it, STATBUS-197'); KEEP the full tail (compose up, DB health wait, reconnect, terminal write, flag handling, maintenance off, window lift). This kills W1 (claim→flag stale pin), W2 (flag→commit stale pin incl. the pull span), and the first-upgrade no-pin CATASTROPHIC abort — the guard sits before the git-restore error branch (:8055).
C3. DELETE ./sb.old INSIDE SERVE-PROVEN COMPLETION (the success-path flag-removal site). Then sb.old-exists ⇔ an unresolved swap ⇔ restoring it is always identity-correct. Kills F3's stale-binary class; C2 is defense-in-depth in front of it.
C4. NO new states, NO flag-format change (same field, earlier population; a pre-rename binary reading BackupPath in an old-sb-upgrading flag performs a real identity restore — safe).

ORACLES (RED first, staggered most-relevant-first):
O1 (AC#2): Go unit — rollback with BackupPath=="" never invokes restoreGitStateFn/restoreBinary; terminal lands rolled_back; tail executes. Seam family: TestRecoveryRollback_ParkedSkipPrecedesRestore.
O2 (AC#3): Go unit source-order pin (extractFuncBody idiom): no `SET backup_path` write precedes the backupDatabase call inside executeUpgrade.
O3 (AC#4): Go unit — completion removes ./sb.old.
O4 (AC#5): the three preswap arcs on a real VM — backup-kill exercises the refusal arm (still ""), checkout-kill NOW exercises the full-restore arm (path stamped at commit; git restored from THIS attempt's pin, DB identity-restore, data intact), binary-swap-kill restores THIS attempt's sb.old.
O5 (optional, King's call): a claim-window KillHere inject class (vocabulary ADDITION) to run-prove W1 end-to-end; the Go seam already pins the disposition.

SEQUENCING: engineer builds AFTER the RC tag lands (tracked files; same hold as 199). Priority raised LOW→MEDIUM on F1/F3 (real defect surface on every multi-upgrade box, not just the sub-second window).
---
<!-- COMMENTS:END -->
