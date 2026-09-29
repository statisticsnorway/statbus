---
id: STATBUS-430
title: >-
  A state-detection failure that clears on rerun says so, not 'correct the
  settings'
status: To Do
assignee: []
created_date: '2026-09-29 08:24'
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
