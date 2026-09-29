---
id: STATBUS-434
title: >-
  Runner-to-niue SSH from GitHub-hosted runners fails intermittently with
  'Network is unreachable'
status: To Do
assignee: []
created_date: '2026-09-29 14:41'
labels:
  - ci
dependencies: []
priority: medium
ordinal: 383200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Evidence 2026-09-29: notify-all-clouds.yaml's runner-online probe (ssh github-runner@niue.statbus.org) failed 7 of 100 runs this month, every one with 'ssh: connect to host niue.statbus.org port 22: Network is unreachable' on the first attempt (runs 36462549188, 36401903903, 36271309498, 36232080575, 36184526678, 36134269827, 36043290540, and 36583650216 attempt 1 on e069fbcfe; its rerun passed). niue has both A 162.55.61.141 and AAAA 2a01:4f8:1c1e:732e::1. Hypothesis to verify: some hosted runners resolve the AAAA record without a working IPv6 route, and ssh gives up instead of falling back to IPv4. The same host is used by deploy-to-dev.yaml, demo-auto-apply-stable.yaml, docker-maintenance.yaml and seq-logserver.yaml, so a red there may be the same cause. There are no flaky tests: find the cause, then fix it for every workflow that dials niue.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The cause of the intermittent 'Network is unreachable' is shown with evidence (e.g. address family attempted, runner network config)
- [ ] #2 Every workflow that SSHes to niue connects reliably (e.g. ssh -4 / AddressFamily inet if IPv6 is the cause), with the reason in a comment
- [ ] #3 No 'Network is unreachable' failure in the next 50 runs of the affected workflows
<!-- AC:END -->
