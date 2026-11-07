---
id: STATBUS-576
title: >-
  The upgrade backup line states the snapshot size, not only the bytes newly
  copied
status: Done
assignee: []
created_date: '2026-11-07T19:07:00Z'
updated_date: '2026-11-07T21:02:00Z'
labels:
  - upgrade
  - ux
dependencies: []
type: bug
ordinal: 503204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The upgrade's backup line reports the bytes newly written by the incremental rsync (the drop in free disk space), so a box whose database barely changed since its last upgrade reads "Backing up database ... ok (0 B in 12.9s)". The snapshot itself is complete (53 GB at ~/statbus-upgrade-snapshots/pre-upgrade-active on Norway, run U 2026-11-07 19:02 UTC), but an operator reads "0 B" as "nothing was backed up".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The line names the snapshot's size and what changed, e.g. 'ok (53 GB snapshot, 0 B changed, 12.9s)'; a unit test pins the wording for a full first copy and for an unchanged database
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07: RED 1ab14de28 reproduces misleading full/unchanged/unknown snapshot summaries. GREEN 69964cf93 reads the existing root rsync's C-locale --stats and reports logical snapshot size separately from whole-file copied size. Completion now reads e.g. '53.0 GB snapshot, 0 B copied, 12.9s'; missing or ambiguous measurements say unknown. Heartbeats report elapsed time, not an inaccurate disk-free delta. Snapshot publication and rollback ordering are unchanged. Full upgrade package tests passed in 153.7s, focused race tests passed, and coordinator independently reran metrics plus actual production backupDatabase twice on private Docker bind fixtures: '17 B snapshot, 17 B copied' then '17 B snapshot, 0 B copied', with both snapshot contents verified. Logs: tmp/576-{red,upgrade,race,real-snapshot}.log and tmp/test-576-coordinator{,-docker}.log. No Norway mutation. The real upgrade gate still needs to exercise the built candidate, so ticket remains In Progress. The normal happy-upgrade baseline uses the OLD binary for its pre-swap snapshot; inspect candidate-based upgrade arcs for the new completion wording rather than incorrectly asserting it on the old baseline.

2026-11-07 21:02 UTC: actual released-candidate host acceptance observed in Upgrade Arc Harness42412906186, completed/success job128525788075 (boot-migrate-churn-alive-idle). This real LXD arc installs A=cb962d0a8be4aba086ffc7b44013e5875a633e9d (v2026.11.2-rc.03), then runs A's upgrader against its failing B fixture with the real inline-dispatch/rollback crash path. Its product output at20:57:14 reads: 'Backing up database ... ok (112.9 MB snapshot, 112.9 MB copied, 8.3s)'. Evidence tmp/rc03-boot-migrate-churn-alive-idle.log: candidate base at lines681/690/744, actual completion wording line859, successful real crash/recovery convergence line1046. The unchanged-copy case was already proven through the actual production backupDatabase twice on private Docker fixtures (17 B snapshot/17 B copied, then17 B snapshot/0 B copied, contents verified), plus full/incremental/unknown-size unit coverage and upgrade-package/race suites. This is candidate-built updater output, not the old stable binary's happy-upgrade backup line. Both the logical snapshot size and copied bytes are now independently named and actual candidate host behavior is observed. Ticket acceptance is complete; the wider33-arc/fault-fleet release gate is still running and is not claimed complete here.
<!-- SECTION:NOTES:END -->
