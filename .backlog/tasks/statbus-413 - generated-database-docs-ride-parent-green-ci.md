---
id: STATBUS-413
title: >-
  A push that changes only generated doc/db files rides the parent green runs
  and retags its images
status: In Progress
assignee: []
created_date: '2026-09-24 23:55'
updated_date: '2026-10-26 19:31'
labels:
  - release-bug
  - ci
  - release
dependencies: []
priority: medium
type: bug
ordinal: 364000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A push that only regenerates the database reference docs costs no CI time, while every commit still ends up with images and a release gate that can vouch for it.

### Zoom out
`doc/db/table/`, `doc/db/view/` and `doc/db/function/` are generated from the database schema by `./dev.sh generate-doc-db`. Their content follows from the parent commit, so rebuilding and retesting a commit that changes only them proves nothing new. Such a commit should be treated like a board-only (`.backlog/`) commit:
- **Tests ride:** Go and app workflows skip the push, and the release gate takes the first-parent commit's green verdicts, naming the parent and the runs it rides.
- **Images retag:** every commit must still have pullable images, so Images copies the parent's images to the new SHA instead of building.

The exemption is narrow by design. Hand-written files elsewhere under `doc/db/`, any other doc, code, migrations and mixed commits always run fresh. One list (`ops/release/ci-exempt-paths.txt`) defines what is exempt, and the workflow filters must match it.

### Zoom in
- **Incident, 2026-09-24:** `10f094f2b` changed only two `doc/db/` files, yet Go Test `36062511490`, app build & lint `36062511473` and a full Images build `36062511465` all ran.
- **Shipped (v2026.09.3):** `2bdb7bdad` (merge `eec893ed2`, branch `ci/docdb-exempt`, now merged) adds the three generated directories to `ops/release/ci-exempt-paths.txt` and to the `paths-ignore` of `go-test.yaml` and `app_build_and_lint-workflow.yaml`. The release gate's existing first-parent ride (`findExemptRide`, `cli/cmd/release/release.go`) and Images' existing retag path then apply.
- **Proof, unit:** `TestFileIsCIExempt_AnchoredPrefixNotSubstring` (including `doc/db/README.md` not exempt), `TestChangedFilesAllExempt_OneOffenderForbidsTheRide`, `TestCIExemptPathsFile_IsNotItselfExempt`, `TestFindExemptRide_*` (`cli/cmd/release/release_ci_exempt_ride_test.go`), `TestPathsIgnoreMatchesExemptList_STATBUS224` (`workflow_triggers_test.go`). Green 2026-10-15.
- **What remains (owner, 2026-10-26):** only the natural end-to-end observation in AC4. Do not manufacture a docs-only push to prove it. When a genuine change consists solely of generated `doc/db/{table,view,function}/` files, record the parent and tip SHAs, confirm Go and app workflows do not run, Images retags the parent, and release preflight names the green parent runs it rides. Then check AC4 and close. Until then the code stays as it is; nothing is reimplemented.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; `ops/release/ci-exempt-paths.txt` documents each entry.
- **Cleanup:** merged branch `ci/docdb-exempt` deleted 2026-10-15.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Only generated `doc/db/{table,view,function}/` paths join `.backlog/` as exempt; hand-written `doc/db/` files, other docs, code, migrations, mixed commits and the policy file itself are not (`TestFileIsCIExempt_AnchoredPrefixNotSubstring`, `TestChangedFilesAllExempt_OneOffenderForbidsTheRide`, `TestCIExemptPathsFile_IsNotItselfExempt`)
- [x] #2 The Go and app workflow `paths-ignore` lists match the exempt list (`TestPathsIgnoreMatchesExemptList_STATBUS224`)
- [x] #3 The release gate rides only a green first-parent ancestor and refuses a red or missing one (`TestFindExemptRide_*`)
- [ ] #4 A genuine, naturally occurring push changes only generated doc/db/{table,view,function}/ files (no artificial proof commit, owner 2026-10-26): Go and app workflows do not run, Images retags the parent, and release preflight rides the parent's green runs. Record parent/tip SHAs and run IDs here, check this, and set Done
- [x] #5 [Owner] Decided 2026-10-26: wait for a natural doc/db-only push; do not manufacture one. Observation is criterion 4
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** green in Go Test (v2026.09.3); re-run green locally on master, 2026-10-15.
- **AC4:** open. Checked 2026-10-15: of 20 first-parent pushes touching `doc/db/` since `eec893ed2`, none changed only generated docs (the one candidate, `a9220be97`, is a merge).

### Unrelated decision kept for the record
It shipped in the same merge as STATBUS-420 (completed, so not editable here) and was written into this ticket:

**Owner decision, 2026-09-25 13:35Z: option D — delete the guard**

The retired-role string guard (`TestRetiredUpgradeRoleAppearsNowhere`, cli/cmd/upgrade_role_retired_test.go) is deleted. Owner's analysis, confirmed by the coordinator: the test over-fires (the string in commentary or generated SQL is not the harm) and under-fires (the same design error under a different key name passes). It guards one historical string, not a principle; the design decision lives in the STATBUS-307 ticket and git history, and review is the actual gate. With the guard gone, this ticket's blocker is dissolved: doc/db-only pushes may ride the exemption list on their own merits, after verifying no OTHER Go test or build step consumes doc/db/ (memo: tmp/q1-docdb-exemption.md).

2026-10-26 owner: wait for a natural doc/db-only push. The remaining criterion and Zoom in now say so explicitly; no artificial proof commit.
<!-- SECTION:NOTES:END -->
