---
id: "rhyndn"
title: >-
  stale-resume-latch-docs: two comments describe a pre-039 blanket-rollback
  latch that no longer exists
state: "done"
assignee: []
updated_date: '2026-07-06 15:59'
labels:
  - docs
  - install-recovery
  - upgrade
  - follow-up
group: ""
rank: "000000000178"
dependencies: []
priority: low
origin: "backlog:STATBUS-130"
aliases: ["STATBUS-130"]
type: "docs"
created: "2026-07-03 21:38"
updated: "2026-07-06 15:59"
---

## Goal

FLAGGED by the mechanic during the STATBUS-044 park-scenario build (2026-07-03 night), confirmed against current code, not fixed (outside his assigned scope).

THE STALE CLAIM, in two places: (1) test/install-recovery/scenarios/3-postswap-container-restart-kill.sh header comment and (2) ops/statbus-upgrade.service inline comment both describe a "one-shot Resuming latch — any death during resume always rolls back". CURRENT REALITY (recoverFromFlag's FlagPhaseResuming branch): ground truth gates the direction — GroundTruthAtTarget always resumes FORWARD; positively-Behind rolls back; there is no blanket-rollback latch. The comments predate the STATBUS-039 ground-truth routing, and are now further superseded by the STATBUS-046 park machinery (death budget + same-step-twice + park, commits c1c4cbb7a + f70ede5e4).

THE CHANGE: a doc-comment pass on both files rewriting the recovery description to the current model (039 direction + 046 bounding). No code change. Verify each sentence against recoverFromFlag/resumePostSwap as shipped before writing.

WHY IT MATTERS: these are exactly the comments an operator or future agent reads when diagnosing a mid-upgrade death; a stale "it will roll back" promise is a wrong mental model at the worst moment.

## Final Summary

MERGED into STATBUS-043: two stale comments claiming a pre-039 "always rolls back" latch — exactly the class 043's concept-level sweep kills.
