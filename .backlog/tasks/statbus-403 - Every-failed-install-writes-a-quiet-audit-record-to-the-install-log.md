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
Every failed installation writes a consistently named audit record to the install log while the terminal presents only the operator recovery message. The record is treated as installation history because installation paths do not create an upgrade row.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md`, and `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` (as applicable). Proposed behavior below is not an observation.

`FAILED_INSTALL_HAS_AUDIT_TRAIL` printed on every Finland failure. It was labelled as a violated invariant even though installs have no upgrade row by design.

## Proving scenario

Unit tests route the audit record through the log writer for representative preflight and step failures and inspect terminal streams for the plain recovery message.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every failed installation writes a consistently named audit record to the install log.
- [ ] #2 The audit record describes expected install history in calm language.
- [ ] #3 The terminal presents the plain operator recovery message for the same failure.
<!-- AC:END -->
