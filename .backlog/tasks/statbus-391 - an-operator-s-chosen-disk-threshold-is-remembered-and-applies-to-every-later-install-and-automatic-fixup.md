---
id: STATBUS-391
title: >-
  An operator's chosen disk threshold is remembered and applies to every later
  install and automatic fixup
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 14:53'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Finland v2026.09.2 evidence (2026-09-24)

The triage found the 100 GB check runs on every `./sb install` at
`cli/cmd/install.go:524-538`, while the service-spawned fixup inherits systemd's
environment through `cli/internal/upgrade/exec.go:130-137`. The operator had to
set `STATBUS_MIN_DISK_GB=84` repeatedly, and automatic fixup cannot inherit it.

## Goal

When an operator sets a disk threshold deliberately, StatBus stores it with the
installation's configuration and every later `./sb install`, including the one
the upgrade service spawns, uses that stored value. The default threshold fits
ordinary production hosts.

## Done when

- After one install with `STATBUS_MIN_DISK_GB=84`, a plain `./sb install` and a
  service-spawned fixup both apply 84.
- The stored value is visible in `./sb config show`.
