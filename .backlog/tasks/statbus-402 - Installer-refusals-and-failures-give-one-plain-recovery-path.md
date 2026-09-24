---
id: STATBUS-402
title: Installer refusals and failures give one plain recovery path
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
labels:
  - install
  - error-handling
dependencies: []
priority: high
type: bug
ordinal: 355000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A preflight refusal explains the reason and the one outside fix before installation changes the box. A failure after work begins names the step, states the cause and fix in one sentence, prints the one install command, and gives the support-file path. Shell implementation traces stay in the log.

## Evidence, 2026-09-24

The Finland disk refusal printed shell source, `SYSTEM UNUSABLE`, an unnamed invariant, and a command that depended on the current directory even though installation had not started. Later failures printed internal audit wording rather than one recovery path.

## Proving scenario

Add a forced preflight refusal to `harness-failure-path-selftest.sh` and assert exit 78, the plain reason, the outside fix, and the one install command. Add a post-start failure and assert the step, cause, fix, support-file path, and rerun command.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A preflight refusal prints the plain reason, the one outside fix, and the one install command.
- [ ] #2 A failure after work begins prints the step, cause, fix, one install command, and support-file path.
- [ ] #3 Operator output contains plain recovery guidance while implementation traces remain in the install log.
<!-- AC:END -->
