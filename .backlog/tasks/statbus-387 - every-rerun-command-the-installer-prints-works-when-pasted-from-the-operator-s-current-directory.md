---
id: STATBUS-387
title: >-
  Every rerun command the installer prints works when pasted from the operator's
  current directory
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 15:34'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every instruction to run installation again prints `curl -fsSL https://statbus.org/install.sh | bash`. The command works from the operator current directory and rerunning it converges the installation.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

Finland output printed `./sb install`, while the operator was in the home directory and the program lived under `~/statbus`. It also exposed internal guidance about skipped steps.

## Proving scenario

A source-scanning test covers operator-facing rerun strings. The port-conflict harness scenario pastes the printed command from the home directory and reaches green.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every rerun instruction prints `curl -fsSL https://statbus.org/install.sh | bash`.
- [ ] #2 The printed command works from the operator current directory and converges a partial installation.
- [ ] #3 Rerun guidance describes the operator action in plain words.
<!-- AC:END -->
