---
id: STATBUS-387
title: >-
  Disk refusal remedy must print a rerun command valid from the operator's current directory
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

The refusal suggested `./sb install`, but the operator was in `~` and the
binary was `~/statbus/sb`. The triage cites `cli/cmd/install.go:535` and the
installer directory setup at `install.sh:349`; it also calls out another rerun
hint at `install.go:889`.

## Done when

All rerun hints use the resolved install directory, for example
`cd ~/statbus && STATBUS_MIN_DISK_GB=N ./sb install`, and are valid from the
shell location where install.sh prints them.
