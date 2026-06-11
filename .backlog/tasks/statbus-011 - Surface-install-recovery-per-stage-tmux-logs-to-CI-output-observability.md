---
id: STATBUS-011
title: Surface install-recovery per-stage tmux logs to CI output (observability)
status: Done
assignee:
  - engineer
created_date: '2026-06-07 23:18'
updated_date: '2026-06-11 08:34'
labels:
  - install-recovery
  - ci
  - observability
dependencies: []
references:
  - test/install-recovery/lib/vm-bootstrap.sh
priority: medium
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Inline install-recovery scenarios run `./sb install` in a DETACHED tmux session (via the _start_install_with_env / tmux runner), so its output goes to the VM's /tmp/stageN.log — which is NOT captured in the CI logs or artifacts. This made diagnosing migrate-killed-after-commit's stall-timeout very hard: we couldn't see the second install's "Detected install state" line to tell whether the inline trigger even dispatched the upgrade.

Being addressed now in the overnight grind (engineer adding stage-log surfacing to the shared helper, on both success + failure, before VM reap). This task tracks the finding + verifying the fix covers ALL inline-tmux scenarios (not just migrate), and is the canonical record of the observability gap.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 /tmp/stage*.log surfaced to CI stdout/artifact before VM reap, on success AND failure
- [x] #2 Implemented in the shared helper so all inline-tmux scenarios benefit
- [x] #3 Verified: a failing inline scenario's CI log now shows the per-stage install output (incl. 'Detected install state')
<!-- AC:END -->



## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLOSED (foreman, 2026-06-11): stage-log surfacing landed via b80d725a7 ('test(install-recovery): surface detached-tmux stage logs to CI before VM reap', test/install-recovery/lib/vm-bootstrap.sh +45). Task was never closed after the fix landed; verified by git show.
<!-- SECTION:NOTES:END -->
