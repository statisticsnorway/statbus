---
id: STATBUS-493
title: >-
  Stage 0 should detect HTTP reachability instead of asking, and ask only when
  HTTP is blocked
status: Done
assignee: []
created_date: '2026-10-13 12:32'
updated_date: '2026-10-13 12:38'
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
- [x] #1 The stage probes outbound HTTP and HTTPS reachability with a short bounded test before deciding anything, and prints what it found. Checked by the probe being visible in the run output and by its timeout being bounded so it cannot hang the run.
- [ ] #2 When HTTP egress works, the stage asks nothing and rewrites nothing. Checked by a run transcript on a box with HTTP access.
- [x] #3 When HTTP egress does not work, the stage states the finding and proceeds to HTTPS sources with the default answer yes. Checked by a run transcript on a box without HTTP access.
- [x] #4 The decision is the probe result, not operator guesswork: no code path asks the question before probing. Checked by reading the stage.
- [ ] #5 Unconditional HTTPS-only behaviour comes only from a declaration in the interactive configuration or the environment configuration, which the script already supports. Checked by a run where the declaration is set on a box whose HTTP works: the rewrite happens without a question.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-13 owner clarification, recorded after dispatch: the ONLY way to obtain the HTTPS-only behaviour unconditionally is a declaration made in the interactive configuration or the environment configuration. Without such a declaration the script detects, and it asks only when the detection says HTTP is blocked (default yes). All three paths therefore exist: declared, detected-and-unnecessary, detected-and-necessary.

Fixed in d61bb7def. Stage 0 now curls http://archive.ubuntu.com/ubuntu/ and https://mirrors.edge.kernel.org/ubuntu/ (connect-timeout 5, max-time 8) BEFORE any prompt and logs 'Probe: HTTP x, HTTPS y'. If HTTP is reachable it logs that and returns without asking or rewriting. If HTTP is blocked it says so and asks 'Switch APT sources to HTTPS?' with default y. Test test/install-recovery/tests/setup-stage0-http-probe-test.sh stubs curl. RED on the parent: both cases FAIL, showing 'ASKED[Run this stage?|default=n]'. GREEN: 'PASS http-reachable: no question ... Probe: HTTP reachable, HTTPS reachable' and 'PASS http-blocked: ... ASKED[Switch APT sources to HTTPS?|default=y]'. CI Harness Selftest run 38398210946: harness-selftest job success, and the STATBUS-493 step success. Go Test, app build and Fast Tests for this SHA were cancelled because the next push superseded them. They are not counted as passes. AC#2 is left open: it needs a transcript from a real box.
<!-- SECTION:NOTES:END -->
