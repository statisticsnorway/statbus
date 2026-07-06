---
id: STATBUS-043
title: >-
  docs-done-right: rewrite (not annotate) the stale recovery docs + root
  instruction files + full 039/040/041 doc sweep
status: To Do
assignee:
  - architect
created_date: '2026-06-12 21:51'
updated_date: '2026-07-06 15:59'
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
priority: high
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
<!-- COMMENTS:END -->
