---
id: STATBUS-391
title: Later installation and repair work follows the persisted disk policy chosen at first installation
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - install
dependencies:
  - STATBUS-386
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The installer persists the STATBUS-386 disk-policy choice in `.env.config`. First installation, a new process, service restart, rerun, upgrade, and automatic fixup measure the Docker service-data and backup filesystems with the same 20 GB minimum and 40 GB recommendation.

## Evidence, 2026-09-24

Current first-install code reads an ephemeral environment override and measures `.` (`cli/cmd/install.go:524-538` at master `7a9cf707e`). The automatic upgrade service independently measures `d.projDir` only for reporting and does not apply the selected install threshold (`cli/internal/upgrade/service.go:4689-4703` at master `7a9cf707e`). The rollback-resurrection arc invokes later fixup (`test/install-recovery/arcs/c-rollback-resurrection-arc.sh:307` at master `7a9cf707e`). Persisting one shared policy across these callers is the target behavior of this ticket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/internal/diskpolicy/policy_test.go::TestSharedThresholdAcrossCallers` gives first install, rerun, upgrade, and fixup the same free-space values and observes identical refusal, warning, and recommended results.
- [ ] #2 `new: cli/cmd/install_disk_policy_test.go::TestDiskPolicyPersistsInEnvConfig` selects the 20 GB minimum and 40 GB recommendation and observes the same measured locations and values after a new process and service restart.
- [ ] #3 `new: test/install-recovery/scenarios/5-install-disk-threshold-repair.sh` proves the persisted choice survives installation, upgrade, and automatic fixup on the 40 GB VM.
<!-- AC:END -->
