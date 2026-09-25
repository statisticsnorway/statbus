---
id: STATBUS-402
title: Installer refusals and failures give one plain recovery path
status: In Progress
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-24 18:42'
labels:
  - release-bug
  - install
  - error-handling
dependencies:
  - STATBUS-387
priority: high
type: bug
ordinal: 355000
---

## Status 2026-09-24

**In Progress.** `8543f493a`, `373d15fc3`: `cli/cmd/install_operator_output_test.go` and `install_failure_cause_test.go` cover plain guidance and redaction (#1 partly). The named post-start failure test and vocabulary test (#2-3) are absent; `harness-failure-path-selftest.sh` exists but does not by itself prove installer exit-78 wording. **Remaining:** assert all preflight/post-start outcomes, complete rerun/support path, and operator/internal vocabulary separation.

## Release gate observation 2026-09-25

v2026.09.3 rc.02 failed `1-boot-concurrent-install` in [Actions run 36104217764, job 107973800359](https://github.com/statisticsnorway/statbus/actions/runs/36104217764/job/107973800359): a second installer correctly refused an install-held live mutex, but printed `An upgrade is already running` instead of naming the installation. The flag already records `holder=install` and `started_at`; no PID is stored (flock is the liveness proof). The targeted fix uses the flag owner and start time in plain operator wording and retains the `lsof` process-inspection hint. The concurrent-install VM scenario remains proof pending until rerun; this observation does not complete AC #1-3.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A deliberate preflight refusal explains the reason and one outside fix before changes begin, exits 78, and prints the complete rerun command with selected channel and unattended options. A failure after work begins names the step, cause, fix, rerun command, and support-file path. Operator output avoids implementation vocabulary while detailed traces remain in the log.

## Evidence, 2026-09-24

The Finland disk refusal printed shell source, `SYSTEM UNUSABLE`, an unnamed invariant, and a directory-dependent command (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:14-35`). Current bootstrap refusal handling is at `install.sh:770-792`, and Go refusal classification is at `cli/cmd/install.go:95-101`, both at master `7a9cf707e`. The existing harness self-test path is `test/install-recovery/tests/harness-failure-path-selftest.sh` at master `7a9cf707e`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `test/install-recovery/tests/harness-failure-path-selftest.sh` covers a deliberate preflight refusal and observes exit 78, plain reason, one outside fix, and the STATBUS-387 rerun command with selected options.
- [ ] #2 `new: test/install-recovery/tests/installer-post-start-failure-output-test.sh` forces a post-start failure and observes the step, cause, one fix, rerun command, and support-file path with a non-78 failure exit.
- [ ] #3 `new: test/install-recovery/tests/installer-output-vocabulary-test.sh` rejects `invariant`, `guard`, `flock`, shell source, and internal state names in operator output while confirming those traces remain in the install log.
<!-- AC:END -->
