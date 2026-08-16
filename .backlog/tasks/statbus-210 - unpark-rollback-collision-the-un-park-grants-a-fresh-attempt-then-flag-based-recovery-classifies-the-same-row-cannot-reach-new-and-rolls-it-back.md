---
id: STATBUS-210
title: >-
  unpark-rollback-collision: the un-park grants a fresh attempt, then flag-based
  recovery classifies the same row cannot-reach-new and rolls it back
status: To Do
assignee: []
created_date: '2026-08-16 22:29'
labels:
  - upgrade-recovery
  - release
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/cmd/install.go
  - test/install-recovery/arcs/un-park-to-completion-arc.sh
  - doc/upgrade-recovery-model.md
priority: high
ordinal: 210000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: `./sb install` on a parked row un-parks it for ONE fresh attempt that runs to completion (STATBUS-159/111 contract); recovery never destroys the attempt it just granted.
> FOUND: overnight arc triage 2026-08-17, v2026.08.0-rc.01 arc run 31970534502, un-park-to-completion (job 95222618650) — genuine product failure, ran post-stampede (17 min real execution, codeonly fixture lineage — NOT the crollback-image defect).

SEQUENCE (from the arc's captured install output, timestamps 22:22-22:23): row id=2 parked on disk-full ("4 GB free < 5 GB needed before image-pull"); the arc frees the disk (30 GB), operator-triggers `./sb install`. Install detects crashed-upgrade (flag present, flock free), quiesces the unit SIGKILL-class, then: "crash recovery: UN-PARKED upgrade id=2 — ./sb install grants ONE fresh attempt with a reset budget" — CORRECT so far. Then immediately: "Recovering an interrupted upgrade — found a service marker for ca74bb57" → resume classifier: "binary commit 5d141d3c != row target ca74bb57 and is not its descendant (upgrade crashed before binary swap)" → observed-state=cannot-reach-new → "UPGRADE_DIED_DURING_RESUME ... rolling back" → full rollback with DB restore, exit 75. The arc expected exit 0 (the fresh attempt completes with the disk freed).

THE DEFECT SHAPE: after un-parking, the row (in_progress, service flag marker still naming target ca74bb57) is indistinguishable to the flag-based recovery classifier from a crashed mid-flight upgrade — so instead of DISPATCHING the granted fresh attempt, RecoverFromFlag's classification rolls the row back and destroys the un-park's intent. Open design questions for the architect (recovery-semantics core — his ruling, possibly the King's morning word if it touches the ratified park/un-park contract): should the un-park clear/rewrite the flag phase marker so recovery re-dispatches instead of classifying? Should the un-park path bypass the resume classifier entirely and go straight to executeUpgrade for the row? Is cannot-reach-new even correct here (the binary at 5d141d3c is the SOURCE, the row target ca74bb57 is a FIXTURE branch commit — descendant checks can't apply to fixture lineages, but that's the arc's realism, not an excuse)?

This is also STATBUS-200's AC#2 observation arc — that criterion stays open pending this fix.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect ruling on the un-park→dispatch path: how the granted fresh attempt survives the flag-based recovery classifier (clear/rewrite marker, bypass classifier, or reclassify) — within or explicitly escalating the ratified park contract
- [ ] #2 Fix landed: un-park → the SAME row runs its fresh attempt to completion; recovery never rolls back a row it just un-parked
- [ ] #3 un-park-to-completion green at an RC tag (also closes STATBUS-200 AC#2)
<!-- AC:END -->
