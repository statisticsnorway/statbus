---
id: STATBUS-042
title: >-
  upgrade-doc-drift: refresh upgrade-timeline.md +
  install-recovery/upgrade-timeline/upgrade-lifecycle diagrams to 039/040
status: To Do
assignee:
  - architect
created_date: '2026-06-12 21:36'
labels:
  - docs
  - upgrade
  - diagrams
dependencies: []
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
- [ ] #1 upgrade-timeline.md no longer references pickLatestBackup as live; identity-keyed restore + verifyBinaryGroundTruth tri-state documented; conservative-false corrected
- [ ] #2 install-recovery + upgrade-timeline + upgrade-lifecycle .plantuml updated to post-039 routing/restore/SIGKILL-takeover; .svg regenerated from each
- [ ] #3 Deploy-stop contract (040/041: callers never pre-stop) reflected where the deploy path is drawn
- [ ] #4 A reader of the upgrade docs sees the post-039 architecture with no references to deleted code
<!-- AC:END -->
