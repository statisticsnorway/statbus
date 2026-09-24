---
id: STATBUS-391
title: >-
  Later install and repair work follows the same measured disk policy as first
  installation
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 15:35'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
First installation, reruns, upgrades, and automatic repair use the same measured disk locations and thresholds. The warning band remains a warning during later work, so a box accepted at installation continues through routine repair.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

The Finland run needed an internal disk override. Separate automatic fixup code could apply a different threshold later, making the accepted choice unstable across runs.

## Proving scenario

Unit coverage feeds the same free-space values to first-install and later-fixup checks and receives the same refusal, warning, and recommended results. Install-recovery arcs run on ordinary 40 GB VMs and complete both install and repair.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 First installation, reruns, upgrades, and automatic repair measure the same service-data and backup locations.
- [ ] #2 Each path applies the same starting minimum and recommended capacity.
- [ ] #3 A box in the warning band completes routine install and repair work.
<!-- AC:END -->

## Review correction 2026-09-24

First-install measurement is `cli/cmd/install.go:524-538`; cite the actual later automatic-fixup implementation rather than inferring it from the audit (`test/install-recovery/arcs/c-rollback-resurrection-arc.sh:307` is only a current test anchor). Record the minimum, recommendation, persisted operator choice, and measured locations. Add a named shared-threshold unit test and **new** `test/install-recovery/scenarios/5-install-disk-threshold-repair.sh`, proving the choice persists across a new process, service restart, upgrade, and fixup.
