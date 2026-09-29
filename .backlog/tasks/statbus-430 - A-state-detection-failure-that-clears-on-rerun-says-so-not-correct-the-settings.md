---
id: STATBUS-430
title: >-
  A state-detection failure that clears on rerun says so, not 'correct the
  settings'
status: In Progress
assignee: []
created_date: '2026-09-29 08:24'
updated_date: '2026-09-29 13:30'
labels:
  - install
dependencies: []
priority: medium
ordinal: 379200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the Ville replay (tmp/ville-replay-v2026.09.3.md D4, 2026-09-29). Attempt 2 on the repaired box failed state detection with 'FATAL: the database system is shutting down' (psql over the db socket). cli/cmd/install.go:547 returns 'the install state could not be determined safely; nothing was changed. Run the same install command again ...', but install.sh's exit-78 fallback (install.sh:859) prints 'Installation cannot start with the current settings. Correct the settings, then run: ...', which is wrong: nothing about the settings was wrong. Also find what restarted the database between attempt 1 (Settings refusal) and attempt 2 (likely the upgrade daemon restarting under the swapped binary and converging the db container while install ran) and whether install and daemon must serialise there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 install.sh shows the Go sentence for a state-detection failure (allowlisted, full-line anchored) instead of the settings sentence
- [ ] #2 The cause of the database restart between attempts is identified with evidence, and either prevented or documented as expected with the rerun remedy
- [ ] #3 A test covers the detection-failure message path
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-29: fix on fix/430-detection-message (8dd6a68d6). Review tmp/review-430.md: MERGE WITH CHANGES (A: new allowlist entry is only prefix-anchored, so arbitrary trailing text crosses the log boundary; print the trusted rerun command and a validated bundle path from the shell, and $-anchor the existing port/disk/restart members; B: test should drive the real Go error and add negatives; C: comment wording). AC2 cause confirmed by review: a 09.2 unit left in a Restart=always loop re-execs the swapped binary, whose boot Pre-flight A/B (config generate + up -d db, no install mutex) recreates the db container while install runs. Filed as STATBUS-432.
<!-- SECTION:NOTES:END -->
