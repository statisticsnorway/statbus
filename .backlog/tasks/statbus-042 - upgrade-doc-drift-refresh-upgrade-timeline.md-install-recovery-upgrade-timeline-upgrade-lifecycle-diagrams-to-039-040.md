---
id: STATBUS-042
title: >-
  upgrade-doc-drift: refresh upgrade-timeline.md +
  install-recovery/upgrade-timeline/upgrade-lifecycle diagrams to 039/040
status: Done
assignee:
  - architect
created_date: '2026-06-12 21:36'
updated_date: '2026-06-12 21:46'
labels:
  - docs
  - upgrade
  - diagrams
dependencies: []
modified_files:
  - doc/upgrade-timeline.md
  - doc/diagrams/install-recovery.plantuml
  - doc/diagrams/install-recovery.svg
  - doc/diagrams/upgrade-timeline.plantuml
  - doc/diagrams/upgrade-timeline.svg
  - doc/diagrams/upgrade-lifecycle.plantuml
  - doc/diagrams/upgrade-lifecycle.svg
  - doc/recovery/recovery-arc-flaw-timeoutstartsec.md
  - doc/recovery/upgrade-resume-structural-whole.md
priority: high
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
STATBUS-039 and STATBUS-040 shipped touching ZERO doc/ files (verified: `git show --stat 5eacd6305 f5b697928 -- doc/` is empty). The upgrade/install docs + diagrams now describe the PRE-039 architecture — including code that no longer exists.

## Verified staleness
- `doc/upgrade-timeline.md:460` describes `pickLatestBackup` as live snapshot-selection behavior. 039 DELETED that function — only tombstone comments + a test-guard forbidding the symbol remain in code (`cli/internal/upgrade/postswap_test.go:456`). The doc presents deleted code as current.
- `doc/upgrade-timeline.md:480` describes routing as "`binaryDescendsFlag`, with `git merge-base` errors conservative-false". 039 review-finding-1 changed exactly this: a merge-base ERROR is now `Unknown → forward` (not conservative-false → restore), via the new `verifyBinaryGroundTruth` tri-state — which the doc never mentions.
- The PlantUML diagrams all predate 039: `install-recovery.plantuml/.svg` (Jun 7), `upgrade-timeline.plantuml/.svg` (Jun 11), `upgrade-lifecycle.plantuml/.svg` (Jun 4). None show: ground-truth-first tri-state routing (AtTarget/Behind/Unknown), identity-keyed restore (only the upgrade's own backup_path), the SIGKILL-class takeover (mask→SIGKILL→verify-dead→stop→unmask, never SIGTERM), or flock-serialized recovery.
- 040's removal of the standalone.sh pre-install SIGTERM stop is reflected in no diagram.

## Scope
1. `doc/upgrade-timeline.md`: replace pickLatestBackup/latest-backup language with identity-keyed restore; document the verifyBinaryGroundTruth tri-state and the corrected git-error→Unknown→forward semantics; remove "conservative-false" where 039 changed it.
2. `doc/diagrams/install-recovery.plantuml`, `upgrade-timeline.plantuml`, `upgrade-lifecycle.plantuml`: update to the post-039 routing/restore/takeover; regenerate the `.svg` from each `.plantuml`.
3. Add the deploy-stop contract (040 standalone + 041 cloud) where the deploy path is drawn.

## Freeze-safety
Doc-only — not in rc.02, not on rune, not in the battery. Freeze-safe. Can run in parallel with the rune recovery.

## Queue
After STATBUS-041 (cloud.sh). Architect wrote 039+040, has warm context.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 upgrade-timeline.md no longer references pickLatestBackup as live; identity-keyed restore + verifyBinaryGroundTruth tri-state documented; conservative-false corrected
- [x] #2 install-recovery + upgrade-timeline + upgrade-lifecycle .plantuml updated to post-039 routing/restore/SIGKILL-takeover; .svg regenerated from each
- [x] #3 Deploy-stop contract (040/041: callers never pre-stop) reflected where the deploy path is drawn
- [x] #4 A reader of the upgrade docs sees the post-039 architecture with no references to deleted code
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Committed 0360caeb0 (9 files, +185/−87, pushed; the repo's pre-commit hook regenerated the SVGs — manual regen matched). upgrade-timeline.md: the recoverFromFlag section rewritten to the post-039 routing (PreSwap restore no-op BY IDENTITY; Resuming ground-truth-gated tri-state — AtTarget/Unknown forward, only positively-Behind restores the upgrade's OWN snapshot; FLAG_PHASE_UNKNOWN fail-loud; the deleted headSHA self-heal segment documented as deleted, with the live self-heals named at resumePostSwap's canary + completeInProgressUpgrade); verifyBinaryGroundTruth tri-state documented (exit-1 = the only Behind; git errors = Unknown → forward); "conservative-false" removed; the live-upgrade ladder row + decision tree gained the SIGKILL-class takeover arm; the terminal-tiers section now leads with "ground truth decides what runs" and carries the shipped error strings (the deleted formatForwardRecoveryFailure strings removed); TimeoutStopSec ties to the never-pre-stop deploy contract; the FALSE "text-file-busy avoided by cloud.sh systemctl stop" claim replaced with the rename-atomicity truth + STATBUS-040/-041 pointers. Diagrams: upgrade-lifecycle gained the in_progress forward-retry self-loop + verdict-gated terminals + the identity/flock note; upgrade-timeline gained the tri-state Resuming alt, the deploy-contract note, the NRestarts dispatch reset, and updated cell (2)/(e) mechanics; install-recovery gained the probe-2 takeover sub-branch (crash-looping → SIGKILL-class quiesce → treat as crashed; progressing → refuse). Historical records annotated, not rewritten: recovery-arc-flaw's stop-first "sanctioned path" carries a dated DO-NOT-FOLLOW supersession banner; upgrade-resume-structural-whole's CHANGE-2 H2/H3 + guarantee lines point at the identity-keyed replacement. Beyond-plan finds, flagged to foreman: (a) scenario 3-postswap-resume-died-rollback asserts the PRE-039 latch (always rolled_back) — an at-target fabrication now converges FORWARD; expectation must be updated BEFORE the next battery run (noted in the diagram's TEST note); (b) the two doc/recovery files contained actively dangerous guidance (the stop-first path) and presented deleted code as shipped — both now superseded-annotated. Final sweep: zero references to deleted code as live anywhere in doc/ outside dated supersession notes.
<!-- SECTION:FINAL_SUMMARY:END -->
