---
id: STATBUS-386
title: On low disk space, the installer states what is free, what is needed, and how to continue
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - release-bug
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Status 2026-09-24

**In Progress.** `2aea9e733`, `373d15fc3`: `cli/internal/diskpolicy/policy.go` and `policy_test.go::TestSharedThresholdAcrossCallers` implement the 20/40 GB policy (#1-3 partly); the three named `cli/cmd/disk_policy_test.go` cases are absent. `4-install-40gb-disk.sh` exists, but #4 is proof pending on a real VM. **Remaining:** add the three installer-band assertions and run the 40 GB VM measurement.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The disk policy measures the filesystem containing Docker service data and the filesystem containing StatBus backups. Installation refuses below 20 GB free, warns and continues from 20 GB through 39 GB, and recommends at least 40 GB. A refusal names the measured location, free space, 20 GB minimum, and complete rerun command.

## Evidence, 2026-09-24

Current first-install behavior measures the current directory and defaults to a 100 GB refusal threshold (`cli/cmd/install.go:524-538` at master `7a9cf707e`). The Finland laptop had 85 GB free and was refused, then the printed directory-dependent override failed from the home directory (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:14-36`). The 20 GB minimum and 40 GB recommendation are the target policy selected by this ticket. The audit previously described 20 GB only as a proposal (`/Users/jhf/ssb/statbus/tmp/installer-message-audit.md:72-84`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/disk_policy_test.go::TestDiskPolicyBelowMinimum` measures both configured filesystems and, below 20 GB, reports the location, free space, 20 GB minimum, and complete rerun command.
- [ ] #2 `new: cli/cmd/disk_policy_test.go::TestDiskPolicyWarningBand` observes installation continue with a warning from 20 GB through 39 GB.
- [ ] #3 `new: cli/cmd/disk_policy_test.go::TestDiskPolicyRecommendedBand` observes installation continue with the recommendation satisfied at 40 GB or more.
- [ ] #4 `new: test/install-recovery/scenarios/4-install-40gb-disk.sh` uses the harness's 40 GB VM, completes installation, and records the measured service-data and backup filesystems.
<!-- AC:END -->
