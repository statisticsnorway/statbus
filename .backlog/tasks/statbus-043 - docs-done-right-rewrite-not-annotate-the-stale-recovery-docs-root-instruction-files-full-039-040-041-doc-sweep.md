---
id: STATBUS-043
title: >-
  docs-done-right: rewrite (not annotate) the stale recovery docs + root
  instruction files + full 039/040/041 doc sweep
status: To Do
assignee:
  - architect
created_date: '2026-06-12 21:51'
updated_date: '2026-07-12 03:30'
labels:
  - docs
  - upgrade
  - install-recovery
dependencies: []
references:
  - doc/recovery/recovery-arc-flaw-timeoutstartsec.md
  - doc/recovery/upgrade-resume-structural-whole.md
  - CLAUDE.md
  - AGENTS.md
  - doc/CLOUD.md
  - doc/DEPLOYMENT.md
  - STATBUS-042
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: documents are true — a reader of any doc, comment, or diagram sees only the shipped system.
> BENEFIT: removes the wrong-mental-model class at its source: the two recovery docs still teach the pre-039 model under banners, CLAUDE.md/AGENTS.md still describe a refuse-only install ladder, and stale "it will roll back" promises sit exactly where an operator or agent looks mid-incident. Scope now includes post-046/park-arc drift.
> STAGE: Stage 1 docs.
> COMPLEXITY: architect-design (concept-level rewrite, not annotation; assigned).
> DEPENDS ON: nothing hard; soft-after STATBUS-107's vocabulary registry for the recovery files (avoids re-touching them with pre-registry words).

---

King directive (2026-06-12): documents must be TRUE — the working tree is the present, git is the history. Banners over wrong content are half-measures.

SCOPE (all verified stale):
1. doc/recovery/recovery-arc-flaw-timeoutstartsec.md — body still walks the stop-first "sanctioned path" (the deploy-stop footgun) under a supersession banner added in STATBUS-042. REWRITE the operational guidance to the current truth (one command: ./standalone.sh install <name>; install refuses-or-takes-over itself) or move the document to an archive location out of the reading path. The historical ANALYSIS (why the wedge happened) may stay as analysis — clearly past-tense, never as instructions.
2. doc/recovery/upgrade-resume-structural-whole.md — CHANGE-2 H2/H3 body still describes pickLatestBackup mechanics + TestPickLatestBackup_* guards as shipped, under bracketed notes. Rewrite those passages to the identity-keyed reality (restore consumes only flag.BackupPath/row.backup_path; guards are the identity-contract tests) — the rename state machine content is current and stays.
3. CLAUDE.md:88 — install ladder rung 2 says "live-upgrade — flag present, holder PID alive → refuse". Post-039: flock-held + crash-looping (NRestarts≥3) → SIGKILL-class takeover; progressing → refuse. Also re-verify the whole "Install / Upgrade" section against the shipped ladder.
4. AGENTS.md:112 — same stale row ("Refuse with diagnostic; do not touch state") in the dispatch table; same fix.
5. FULL SWEEP of the remaining docs for 039/040/041 impact — doc/CLOUD.md, doc/DEPLOYMENT.md, doc/install-statbus.md, doc/INTEGRATE.md, and the diagrams NOT touched by STATBUS-042 (infrastructure-cloud, git-workflow, architecture, domains-*): any claim about upgrade recovery semantics, rollback conditions, deploy pre-stop, restore selection, or the install ladder must match the shipped contract. Sweep by CONCEPT, not just symbol names (the 042 grep was symbol-based: pickLatestBackup/conservative-false/binaryDescendsFlag/stop_upgrade_service — conceptual drift like "one attempt, NO retry" or "any failure rolls back to the snapshot" needs human reading of each file).

CONTEXT: STATBUS-042 (0360caeb0) fixed doc/upgrade-timeline.md + the 3 lifecycle diagrams and ANNOTATED the two recovery docs; this task finishes the job to the documents-are-true standard and covers the files 042 never opened.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The two doc/recovery files contain NO pre-039 guidance presented as current — operational instructions rewritten to the shipped contract or the file archived out of the reading path; analysis clearly past-tense
- [ ] #2 CLAUDE.md + AGENTS.md install-ladder rows match the shipped dispatch (takeover arm included)
- [ ] #3 Concept-level sweep of CLOUD.md, DEPLOYMENT.md, install-statbus.md, INTEGRATE.md + untouched diagrams completed; every found drift fixed in the same commit
- [ ] #4 A reader of ANY doc in the repo sees only the shipped architecture; supersession banners remain only on genuinely archived material
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer (board sweep)
created: 2026-07-06 15:59
---
FOLDED IN from STATBUS-115 (merged 2026-07-06): same aim (docs describe only the shipped system), same owner, partially done — a named residual list (scrub archive/backup refs) for the 043 sweep.
---

author: engineer (board sweep)
created: 2026-07-06 15:59
---
FOLDED IN from STATBUS-130 (merged 2026-07-06): two stale comments claiming a pre-039 'always rolls back' latch — exactly the class 043's concept-level sweep kills. A named residual for that sweep.
---

author: foreman
created: 2026-07-12 00:00
---
STALENESS FINDINGS for this sweep (mechanic, 2026-07-12, found while adding the read-only-window cost paragraph): (1) doc/read-only-upgrade-window.md's exemption section says the authenticator exemption is 'durable in a migration ... (migration 20260703104910)' — that migration was DELETED (never in a released tag); the real mechanism home is migrations/post_restore.sql (re-armed on every migrate up) + postgres/init-db.sh (armed at cluster birth). (2) Backlog doc-023 carries the identical staleness ('New migration: ALTER ROLE authenticator ...' as the delivery vehicle). (3) Lower confidence, needs a verification pass: the same doc's many service.go line citations (:4201/:4223/:4227/:4249/:4828/:4859+/:5684, connect() ~2746-2780) predate the STATBUS-145 floor rewrite and STATBUS-154's terminalUpdate consolidation (which deleted per-terminal write functions the doc cites as OFF co-location sites). Note: the architect's pending 110 AC-3 pass (the 039 supersession + decision-tree update) rewrites parts of this doc anyway — coordinate so the fix lands once.
---

author: foreman
created: 2026-07-12 03:30
---
SCOPE REDUCTION (2026-07-12): comment #3's findings 1-3 (the read-only-window doc's deleted-migration citation, doc-023's identical staleness, and the stale service.go line cites) are DONE — fixed by the architect's 110 AC-3 doctrine pass, shipped bd94737e2 (repo docs) + the doc-023 delivery-status note (backlog). The full 043 sweep should NOT re-touch doc/read-only-upgrade-window.md or doc/upgrade-recovery-model.md — both were re-verified line-by-line against the shipped tree in that pass. The sweep's remaining scope is unchanged: the two doc/recovery files, CLAUDE.md/AGENTS.md install-ladder rows, and the concept-level sweep of CLOUD/DEPLOYMENT/install-statbus/INTEGRATE + untouched diagrams.
---
<!-- COMMENTS:END -->
