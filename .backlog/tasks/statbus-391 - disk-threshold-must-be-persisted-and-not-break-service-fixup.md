---
id: STATBUS-391
title: >-
  Disk threshold overrides must survive install and service-spawned fixups
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 16:42'
labels:
  - install
priority: high
type: bug
ordinal: 1
---

## Finland v2026.09.2 evidence (2026-09-24)

The triage found the 100 GB check runs on every `./sb install` at
`cli/cmd/install.go:524-538`, while the service-spawned fixup inherits systemd's
environment through `cli/internal/upgrade/exec.go:130-137`. The operator had to
set `STATBUS_MIN_DISK_GB=84` repeatedly, and automatic fixup cannot inherit it.

## Done when

A deliberate threshold override is persisted or the fixup has an explicit
policy, and ordinary hosts are not blocked by an inappropriate hard refusal.
