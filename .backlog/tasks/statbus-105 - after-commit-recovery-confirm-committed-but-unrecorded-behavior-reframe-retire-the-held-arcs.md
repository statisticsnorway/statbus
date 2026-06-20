---
id: STATBUS-105
title: >-
  after-commit-recovery: confirm committed-but-unrecorded behavior +
  reframe/retire the held arcs
status: To Do
assignee: []
created_date: '2026-06-20 10:48'
labels:
  - upgrade
  - recovery
  - install-recovery
  - arc
dependencies:
  - STATBUS-097
priority: medium
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
▶ DRIVE DECISION + STATUS (foreman, 2026-06-20; King-reframed): DEFERRED to a confirming re-run (not a blocker for STATBUS-102). The King reframed the underlying finding: the committed-but-unrecorded migration window is UNDETECTABLE from the ledger, and STATBUS-097 (atomic apply+record) DISSOLVES it — so 097 is the fix regardless of what the re-run shows. This ticket is the empirical CONFIRMATION + the held-arc disposition, NOT the fix (097 is the fix). STATUS: held arcs on master (opt-in, harmless); confirming re-run + reframe/retire pending.

THE FINDING (overnight 2026-06-19/20): the after-commit-before-recorded subprocess-kill arc (run 27856398346) reached upgrade row state 'completed', NOT 'rolled_back'. The migration's outer tx commits (fixture table exists) but the process is killed before the separate db.migration INSERT — a torn state. The code (migrate.go:826-868 non-atomic apply→record; postSwapFailure→rollback; the migrate.go:830-833 comment) all say this should ROLL BACK. The oracle says completed. Overnight every benign explanation was traced + REFUTED in code: (C) arc reads wrong row — OUT (commit_sha filter, arc-helpers.sh:126); (A) mark-then-restore artifact — OUT (restore-THEN-mark, service.go:2197); benign boot-reapply — OUT (restoreGitState removes V's file, so it can't reapply). So it is a LIKELY-REAL recovery-correctness gap (box certifies a torn migration as completed) — pending durable confirmation.

CONFIRMING RE-RUN SPEC (the only remaining oracle; durable run-artifacts, VM journal is ephemeral): instrument the :844 arc to capture (1) ALL public.upgrade rows (id, commit_sha, state, every timestamp) — did ANY B_FULL row EVER hit rolled_back; (2) the post-SIGKILL journalctl SEQUENCE (postSwapFailure | rollback | rsync | restore | resumePostSwap | self-heal | completed) in timestamped order; (3) restore-vs-mark order. DISCRIMINATOR: rollback/restore fired between kill and completed → completed-via-restore-reapply (arc expectation wrong, flip to assert completed); NO rollback → reconcile-without-rollback = REAL GAP.

HELD ARCS (both on master, opt-in scenarios, harmless): :844 subprocess-kill d18789b55; :845 parent-kill d28760544. Disposition once 097 lands: reframe the cell around 097 (assert atomic complete-or-rollback) OR retire both arcs.

RELATIONS: STATBUS-097 (atomicity, the fix — dissolves the window); STATBUS-071 (the arc framework, owns these scenarios). Context engram #1042.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Instrumented re-run of the :844 after-commit arc captures all public.upgrade rows (state-history) + the post-SIGKILL journalctl sequence + restore-vs-mark order on durable run-artifacts
- [ ] #2 Verdict recorded: completed-via-restore-reapply (benign, flip arc expectation) vs reconcile-without-rollback (real gap) — from the captured sequence
- [ ] #3 Held arcs (:844 d18789b55, :845 d28760544) reframed around STATBUS-097 (assert atomic complete-or-rollback) OR retired, once 097's product change lands
<!-- AC:END -->
