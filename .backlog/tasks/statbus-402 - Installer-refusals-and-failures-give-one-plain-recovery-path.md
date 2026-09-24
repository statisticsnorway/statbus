---
id: STATBUS-402
title: Installer refusals and failures give one plain recovery path
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-24 18:42'
labels:
  - install
  - error-handling
dependencies:
  - STATBUS-387
priority: high
type: bug
ordinal: 355000
---

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
