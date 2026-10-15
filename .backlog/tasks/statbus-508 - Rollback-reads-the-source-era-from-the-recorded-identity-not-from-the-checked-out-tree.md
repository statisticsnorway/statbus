---
id: STATBUS-508
title: >-
  Rollback reads the source era from the recorded identity, not from the
  checked-out tree
status: To Do
assignee: []
created_date: '2026-10-15 09:16'
labels:
  - upgrade
  - rollback
dependencies: []
priority: low
ordinal: 434204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: rollback restores the version recorded when the upgrade started; it never works out 'source' from whatever the tree happens to be. EVIDENCE (rc.02 fleet run 38696133051): on a box whose tree was the candidate's, rollback reported 'source serving era cannot be established: restored source compose image for app is statbus-app:fe4a769a, want source commit 4c88d350' - it took 'source' from the checked-out commit. The upgrade flag already records the true source identity (UpgradeFlag.SourceServingImages: reference + immutable image ID per service); sourceServingExpectedImagesWithProof reads the compose model of the tree and only cross-checks it against that record. Owner principle (2026-10-15): declare the facts once and read them, instead of re-deriving them from state that other steps mutate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rollback derives the source serving images from the recorded identity in the upgrade flag
- [ ] #2 A tree that does not match the recorded source is reported as that, by name, instead of producing a wrong source era
- [ ] #3 Test written first and recorded red on the current code, then green
<!-- AC:END -->
