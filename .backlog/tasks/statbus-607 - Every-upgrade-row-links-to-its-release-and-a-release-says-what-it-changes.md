---
id: STATBUS-607
title: Every upgrade row links to its release, and a release says what it changes
status: To Do
assignee: []
created_date: '2026-11-10T21:16:00Z'
labels:
  - upgrade
  - ui
  - release
dependencies: []
priority: high
type: bug
ordinal: 521204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
An operator deciding whether to install a version can read what it changes, from the upgrade page, in one click, for every release and release candidate.

## Zoom out
- The upgrade page (app/src/app/admin/upgrades/page.tsx) links a version's name to its release page, and shows "report a failed upgrade" on a failed row, only when public.upgrade.release_url is set.
- Nothing has written release_url since a594a1745 (2026-03-27, Git-based discovery dropped it from the INSERTs), so every row since has it NULL: no link to the release and no failure-report button. Seen on demo for v2026.11.4-rc.01 (2026-11-10, owner screenshot).
- GitHub has a release for every tag, prereleases included (/releases/tag/<version>), but its body is only "Full Changelog: <compare link>". StatBus has no written release notes, for stable releases either (v2026.11.3's body is one line).

## Zoom in
1. The link: derive the release page from the version tag (https://github.com/statisticsnorway/statbus/releases/tag/<commit_version>) for any row that has a version, so it cannot go missing; retire the release_url column in a migration (one rule, no second copy). This also restores the failure-report button.
2. The notes: decide what a release says and who writes it (generated at the cut from the tickets set Done since the previous tag, hand-written for stable only, or both), and where the upgrade page shows it.

## Order
First task after STATBUS-606 (owner, 2026-11-10).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every upgrade row with a version shows its name as a link to https://github.com/statisticsnorway/statbus/releases/tag/<version>, release candidates included; a test renders a row without release_url and asserts the link
- [ ] #2 A failed upgrade row shows the report-a-failed-upgrade button; a test asserts it for a failed row
- [ ] #3 public.upgrade.release_url is removed by a migration, and nothing in cli/ or app/ reads or writes it
- [ ] #4 [Owner] Decides what a release's notes contain and who writes them (generated from Done tickets at the cut, hand-written for stable, or both). The answer is recorded in this ticket's notes; it either adds the notes work to this ticket or opens a follow-up.
<!-- AC:END -->
