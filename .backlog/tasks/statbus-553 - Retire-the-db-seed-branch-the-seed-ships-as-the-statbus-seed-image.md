---
id: STATBUS-553
title: 'Retire the db-seed branch: the seed ships as the statbus-seed image'
status: In Progress
assignee: []
created_date: '2026-10-30T23:21:00Z'
updated_date: '2026-10-31T02:58:00Z'
labels: []
dependencies: []
type: chore
ordinal: 476204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
Each delivery path for the seed exists once. The statbus-seed image is that path, so nothing still points at the old db-seed branch.

## Zoom out
doc/DEVELOPMENT.md:347: the seed ships as ghcr.io/.../statbus-seed:<commit>, which replaced the db-seed branch. origin/db-seed was last updated 2026-05-26.

## Zoom in
Still left over: the refspec entry +refs/heads/db-seed in cli/internal/upgrade/refspec.go CanonicalRefspecs (redundant under refs/heads/*); the branch itself, local and on origin; and the worktree /Users/jhf/ssb/statbus-db-seed. Installed boxes carry the line in remote.origin.fetch, and NormalizeRefspecs rewrites it on install/upgrade. Not for rc.02/rc.03.

## Closing review
Confirm with rg that nothing reads the branch, that refspec_test covers a box with old db-seed lines, and the owner's decision on deleting the branch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CanonicalRefspecs is the branch wildcard only, and NormalizeRefspecs rewrites a box carrying the old db-seed line to that wildcard (TestNormalizeRemovesRetiredSeedBranchRefspec)
- [x] #2 No code, CI or doc reads the db-seed branch; only tests name it, as old state to remove
- [ ] #3 A stable release containing 14ecf9e42 is installed on every box: SSB-operated slots (dev, demo, no and the other production slots) report that version
- [ ] #4 Then origin/db-seed, the local db-seed branch and the /Users/jhf/ssb/statbus-db-seed worktree are deleted, and a fetch on a box afterwards succeeds
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Grounding 2026-10-31: the branch has been retired since 9ee422652 (2026-06-02, 'the image is the sole seed source'). It was still named in CanonicalRefspecs, which every install and upgrade writes to remote.origin.fetch; the upgrade check runs git fetch with that config. Reproduced in a scratch repo: with the line present and the branch absent, fetch fails with 'couldn't find remote ref refs/heads/db-seed' (exit 128); with the wildcard only, fetch succeeds. So the order is fixed, the same as STATBUS-248: (1) drop the line (done), (2) release it so boxes normalize, (3) only then delete the branch. Done in 14ecf9e42: red tmp/553-red.log (the new test fails on the old list), green tmp/553-green.log (go test ./internal/upgrade ok, go test ./cmd refspec ok, go build ok). Stale comments corrected in .gitignore, install.sh, cli/cmd/seed.go and install-recovery scenario 5; rg check in tmp/553-rg.log. REMAINING, after release: once the stable release that includes 14ecf9e42 is installed on every box, delete the branch and the worktree (AC #3, #4). Do not delete earlier, because boxes still carrying the line would stop discovering upgrades.

CI: Go Test 41150713984 success on 14ecf9e42. rabbit confirmed: goes into rc.04; rabbit pings when a stable containing it is on every box, then AC #3/#4.

14ecf9e42 is in v2026.10.6-rc.04 (tag at bdfbfe1f5). AC #3 waits for the stable release built from it to be installed on every box.

rc.04 failed its gate (STATBUS-382, unrelated). 14ecf9e42 is in v2026.10.6-rc.05 (tag at b6164e846). AC #3 waits for the stable release built from that line to be installed on every box.
<!-- SECTION:NOTES:END -->
