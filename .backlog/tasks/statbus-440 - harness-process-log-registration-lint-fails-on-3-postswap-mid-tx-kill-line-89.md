---
id: STATBUS-440
title: 'harness process-log-registration lint fails on 3-postswap-mid-tx-kill.sh:89'
status: Done
assignee: []
created_date: ''
updated_date: '2026-10-17 16:07'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The harness lint is green on master, so a red lint is a real finding.

### Zoom out
The lint checks that every process a harness scenario launches registers its log. This ticket recorded a lint failure on one scenario.

### Zoom in
- **Found:** `./dev.sh test-harness` failed on `scenarios/3-postswap-mid-tx-kill.sh:89` (log not registered).
- **Resolved by deletion:** that scenario was deleted in `4a5d45913` (11 legacy scenarios superseded by run-proven arcs). The failing line no longer exists.

### Closing review
- **Memory:** none. **Documentation:** none. **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `./dev.sh test-harness` exits 0 on master and the scenario named in the finding no longer exists
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Closed 2026-10-17
- `./dev.sh test-harness` exited 0 on master (tmp/harness-440.log). `test/install-recovery/scenarios/3-postswap-mid-tx-kill.sh` was deleted in 4a5d45913.
<!-- SECTION:NOTES:END -->

## Issue

`./dev.sh test-harness` fails on clean master (c893c1f02 and 4f2fad7d5,
Darwin local) with:

  FAIL: unregistered harness process logs:
    scenarios/3-postswap-mid-tx-kill.sh:89: .log is not registered near its process launch
    scenarios/3-postswap-mid-tx-kill.sh:89: log redirection is not registered

## Evidence

Reproduced on a clean checkout (git stash → fail → git stash pop), so it is not
caused by the rc.07 fleet-assertion repairs. The scenario is not in the default
fleet catalogue (it did not run in the rc.07 fleet), which is why the red lint
did not gate anything. Unknown whether Darwin-local-only or genuine master
breakage; harness-selftest.yaml in CI is green, so possibly
environment-specific (the local run builds sb from source on Darwin).

## Principled fix

Register the launched process's log per the harness contract
(harness_register_log near the launch), or establish why the lint misfires on
this launch shape and teach the lint the pattern. First reproduce on Linux to
rule out a Darwin artifact.
