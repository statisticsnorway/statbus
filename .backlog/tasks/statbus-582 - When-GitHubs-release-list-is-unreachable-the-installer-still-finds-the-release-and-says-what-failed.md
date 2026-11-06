---
id: STATBUS-582
title: >-
  When GitHub's release list is unreachable, the installer still finds the
  release and says what failed
status: In Progress
assignee: []
created_date: '2026-11-06T15:18:00Z'
updated_date: '2026-11-06T15:28:00Z'
labels:
  - bug
dependencies: []
priority: high
ordinal: 494204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rc.14 gate 2026-11-06 (Deploy candidate to dev, run 42240573107): install.sh --channel prerelease printed 'Error: No pre-release published.' while v2026.11.1-rc.14 was published. GitHub's anonymous /repos/.../releases API answered 504 on every call for over 20 minutes (authenticated calls, /releases/latest, git ls-remote and the releases Atom feed all worked; githubstatus said operational). install.sh (prerelease channel) and every statbus.org/rc resolver (ops/rc/install.sh, setup.sh, uninstall.sh) make one anonymous call with no retry, so a GitHub fault reads as 'no release'. The stable channel's /releases/latest call has the same single-try shape.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The rc resolvers and install.sh --channel prerelease retry the release list a bounded number of times with a growing pause
- [x] #2 When the release list stays unreachable they take the newest release from the public releases feed instead, and install it
- [x] #3 When no source answers they say GitHub could not be reached and give the rerun command, never 'no release published'; 'no release published' is said only when GitHub answered without one
- [x] #4 install.sh --channel stable gets the same retry and wording
- [x] #5 test/install-recovery/tests/rc-resolver-test.sh and fresh-installer-test.sh cover each case, red before and green after
- [ ] #6 The next candidate's gate passes Deploy candidate to dev
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
8a1533464. install.sh (stable via releases/latest, prerelease via the releases list) and ops/rc/{install,setup,uninstall}.sh retry the API 4 times with a growing pause, then read the releases feed (prerelease, rc) or the releases/latest redirect (stable). 'Could not reach GitHub ... Run the same command again when GitHub answers.' when nothing answers. test/install/install-release-lookup-test.sh (6 cases) and rc-resolver-test.sh (7 new cases): red before (tmp/582-install-red.log, tmp/582-rc-resolver-red.log), green after. Live, during the 504 outage: the rc lookup fell back to the feed and found v2026.11.1-rc.14 (tmp/582-live-github.log). AC6 = next candidate's gate.
<!-- SECTION:NOTES:END -->
