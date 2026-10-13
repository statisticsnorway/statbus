---
id: STATBUS-493
title: >-
  Stage 0 should detect HTTP reachability instead of asking, and ask only when
  HTTP is blocked
status: To Do
assignee: []
created_date: '2026-10-13 12:32'
labels:
  - install
  - hardening
dependencies: []
priority: high
type: bug
ordinal: 419204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 in the Uganda prepare run. Owner decision 2026-10-13: the HTTPS-sources stage currently asks the operator an open question whose default is no. That is wrong in both directions. If the box can reach the outside over HTTP, there is no reason to ask at all, because the stage is unnecessary. If HTTP is blocked, a quick probe determines that fact, and only then should anything be said, with the default answer yes. The operator must not be asked to guess a network condition the script can measure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The stage probes outbound HTTP and HTTPS reachability with a short bounded test before deciding anything, and prints what it found. Checked by the probe being visible in the run output and by its timeout being bounded so it cannot hang the run.
- [ ] #2 When HTTP egress works, the stage asks nothing and rewrites nothing. Checked by a run transcript on a box with HTTP access.
- [ ] #3 When HTTP egress does not work, the stage states the finding and proceeds to HTTPS sources with the default answer yes. Checked by a run transcript on a box without HTTP access.
- [ ] #4 The decision is the probe result, not operator guesswork: no code path asks the question before probing. Checked by reading the stage.
<!-- AC:END -->
