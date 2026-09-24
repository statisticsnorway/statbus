---
id: STATBUS-386
title: >-
  On low disk space, the installer states how much is free, how much is needed,
  and how to continue
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
The disk check measures the filesystems that hold service data and backups. It warns and continues above the starting minimum, recommends capacity for growth, and gives one plain recovery action below the minimum.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

The Finland laptop had about 85 GB free. The installer refused at a 100 GB threshold and directed the operator to an internal setting and a directory-dependent command.

## Proving scenario

Unit coverage exercises the refusal, warning, and recommended bands. Install-recovery VMs run with their ordinary 40 GB disks and reach green through the warning band using the one install command.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The disk check measures the storage locations used for service data and backups.
- [ ] #2 At or above the starting minimum, installation continues and states the available space and recommended capacity.
- [ ] #3 Below the starting minimum, the installer states the required space, the location to free, and the one install command to continue.
<!-- AC:END -->

## Review correction 2026-09-24

The current first-install check is `cli/cmd/install.go:524-538`; the audit's 20 GB is a suggestion, not policy (`tmp/installer-message-audit.md:79,91`). Before implementation record the actual minimum, recommendation, and measured filesystems. Add named new unit tests for below-minimum, warning-band, and recommended-band results, plus **new** `test/install-recovery/scenarios/4-install-40gb-disk.sh`.
