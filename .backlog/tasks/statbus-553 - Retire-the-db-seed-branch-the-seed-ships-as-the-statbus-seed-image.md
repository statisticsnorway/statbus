---
id: STATBUS-553
title: 'Retire the db-seed branch: the seed ships as the statbus-seed image'
status: To Do
assignee: []
created_date: '2026-10-30T23:21:00Z'
updated_date: '2026-10-30T23:22:00Z'
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
- [ ] #1 CanonicalRefspecs no longer lists db-seed, and NormalizeRefspecs rewrites installed boxes that carry the line (refspec_test covers a box with old db-seed lines)
- [ ] #2 No code, CI or doc reads the db-seed branch (rg check recorded)
- [ ] #3 [Owner] decides whether to delete the db-seed branch, recorded in this ticket's notes. Yes: origin/db-seed, the local branch and the statbus-db-seed worktree are removed. No: they stay.
<!-- AC:END -->
