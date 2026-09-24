---
id: STATBUS-397
title: The harness has enough Hetzner cores to run its test VMs alongside niue
status: To Do
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 14:53'
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

The Hetzner shared-core quota is about 22. Niue uses 16 cores, each CX23 test
VM uses 2 cores, and the arc run takes about 3.5 hours with two VMs at a time.

Goal: the account has enough shared cores for niue plus the harness's planned
concurrency, and harness concurrency is set to fit the approved limit.

## 2026-09-24 status

The owner is sending a Hetzner support request on 2026-09-24. Next step: wait
for the quota response, record the approved limit, and adjust harness
concurrency or scheduling if needed.
