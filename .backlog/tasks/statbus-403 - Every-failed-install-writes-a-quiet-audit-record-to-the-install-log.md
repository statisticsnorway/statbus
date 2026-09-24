---
id: STATBUS-403
title: Every failed install writes a quiet audit record to the install log
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
labels:
  - install
  - logging
dependencies: []
priority: medium
type: bug
ordinal: 356000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every failed installation writes a consistently named audit record to the install log while the terminal presents the operator recovery message. When failure occurs before the successful-install path records its upgrade row, that log entry provides the bounded failed-install history.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md`, and `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` (as applicable). Proposed behavior below is not an observation.

`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:64,123` shows `FAILED_INSTALL_HAS_AUDIT_TRAIL` on Finland failures. Master records successful installs in an upgrade row (`cli/cmd/install.go:2938-3039`); `upgradeRowID == 0` applies only before that write (`cli/cmd/install.go:682-692`).

## Proving scenario

Unit tests route the audit record through the log writer for representative preflight and step failures and inspect terminal streams for the plain recovery message.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every failed installation writes a consistently named audit record to the install log.
- [ ] #2 The audit record describes expected install history in calm language.
- [ ] #3 The terminal presents the plain operator recovery message for the same failure.
<!-- AC:END -->

## Review correction 2026-09-24

Successful installation records completion in an upgrade row (`cli/cmd/install.go:2938-3039`); only a failed install before that point can have `upgradeRowID == 0` (`cli/cmd/install.go:682-692`). Cite Finland transcript lines 64 and 123 directly. Add named new log-writer tests proving one record per failure, no terminal duplication, and no credentials. The positive operator outcome is a plain recovery message and one rerun command.
