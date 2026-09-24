---
id: STATBUS-405
title: >-
  The automatic update service self-check reports a starting service as healthy
  progress
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
labels:
  - upgrade
  - service
  - install
dependencies: []
priority: medium
type: bug
ordinal: 358000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The automatic update service self-check treats its starting state as healthy progress and reports readiness after the service signals READY=1. Recovery guidance names the one install command in plain words.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md`, and `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` (as applicable). Proposed behavior below is not an observation.

The Finland service self-check printed a `NOT RUNNING` box while the service was activating and later reached READY=1.

## Proving scenario

Unit coverage supplies an activating service state. The existing `1-boot-startup-timeout` scenario inspects the journal of a service that proceeds to active and finds only healthy startup progress.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The self-check treats the activating state as healthy startup progress.
- [ ] #2 The final success message follows the READY=1 signal.
- [ ] #3 Recovery guidance prints the one install command in plain words.
- [ ] #4 The `1-boot-startup-timeout` journal shows healthy startup progress for a service that reaches active.
<!-- AC:END -->

## Review correction 2026-09-24

Finland printed `NOT RUNNING` at the exact transcript line 162; current unit-floor logic is `cli/internal/unitfloor/unitfloor.go:110-139`, with installer readiness at `cli/cmd/install.go:2804-2823`. Preserve the confirmed existing `test/install-recovery/scenarios/1-boot-startup-timeout.sh` path and add a named new activating-state unit test. Logs must show no alarm from activating through READY=1, then success after READY=1, while an actually inactive unit produces a truthful alarm in observable order.
