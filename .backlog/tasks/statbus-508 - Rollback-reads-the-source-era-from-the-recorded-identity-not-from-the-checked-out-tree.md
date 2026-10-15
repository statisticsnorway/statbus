---
id: STATBUS-508
title: >-
  A settings/tree version mismatch during rollback is reported as that, not as a
  missing image
status: In Progress
assignee: []
created_date: '2026-10-15 09:16'
updated_date: '2026-10-15 10:16'
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
- [x] #1 A tree that does not match the recorded source is reported as that, by name, instead of producing a wrong source era
- [x] #2 Test written first and recorded red on the current code, then green
- [x] #3 When the recorded source identity exists, it governs the source images and the tree is only cross-checked against it (verified already true in the code: sourceServingExpectedImagesWithProof reads the flag's SourceServingImages)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CORRECTION + FIXED 40ef0ca29. Reading the code against rc.02 showed my ticket premise was wrong: rollback does NOT take 'source' from the tree when the identity was recorded. sourceServingExpectedImagesWithProof already reads the flag's SourceServingImages (reference + immutable image ID) and only cross-checks the tree's rendered compose references against it; the tree governs alone only for legacy pre-capture releases. The rc.02 refusal ('restored source compose image for app is ...:fe4a769a (tag fe4a769a), want source commit 4c88d350') was CORRECT: the generated compose settings named one version (fe4a769a) while the checked-out tree was another (4c88d350), a mixed-era box with no coherent source to start. The real defect was the wording: it read as a missing/unresolvable image and sent the diagnosis down the image path for hours while the db container and image were intact. FIX: when the model's tag is itself an 8-char commit that differs from the tree, the refusal names both versions as a settings/tree mismatch and says how to resolve it; local/digest/other tags keep their message. RED/GREEN: TestSourceServingExpectedImageReferencesNamesModelTreeMismatch - red on the unfixed code with rc.02's exact wording (tmp/fix508-red.log), green after. Full livedb tier + unit + golangci-lint pass. The mixed-era state itself in rc.02 came from the STATBUS-452 defect (fixed in 255a41d72), which is what put the box there.
<!-- SECTION:NOTES:END -->
