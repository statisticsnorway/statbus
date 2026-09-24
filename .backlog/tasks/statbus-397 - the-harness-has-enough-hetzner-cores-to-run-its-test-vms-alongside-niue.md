---
id: STATBUS-397
title: The install-recovery harness schedules paid VMs within the approved Hetzner quota
status: To Do
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 18:42'
labels:
  - harness
  - infrastructure
  - hetzner
dependencies: []
priority: medium
type: task
ordinal: 87
---

## Description

Harness concurrency is derived from the account's approved shared-core quota and current measured reservations. Before a paid run, the scheduler proves that existing servers plus planned test VMs fit the approved value. If an increase is declined, concurrency is fixed at one test VM and paid runs do not overlap other temporary shared-core work.

## Evidence, 2026-09-24

The earlier 22-core quota, 16-core niue use, two-VM concurrency, and 3.5-hour duration are unverified estimates and are not used as operative facts. Install-recovery VMs are paid and have a one-hour minimum (`test/install-recovery/README.md:8-13` at master `7a9cf707e`). The approved quota and dated usage telemetry must be recorded in `new: test/install-recovery/evidence/hetzner-quota.md` before another paid run.

## Acceptance Criteria

- [ ] #1 `new: test/install-recovery/tests/quota-scheduling-test.sh` reads the approved value from `test/install-recovery/evidence/hetzner-quota.md`, sums measured reservations and configured VM concurrency, and refuses a run that exceeds it.
- [ ] #2 `new: test/install-recovery/evidence/hetzner-quota.md` records the dated Hetzner approval and dated server telemetry used by the scheduler.
- [ ] #3 `new: test/install-recovery/tests/quota-scheduling-test.sh` proves the declined-increase fallback enforces one test VM and rejects overlap with other temporary shared-core work.
- [ ] #4 `new: test/install-recovery/tests/quota-scheduling-test.sh` proves an approved higher value permits only the concurrency that fits the recorded quota.
