---
id: STATBUS-387
title: >-
  Every rerun command the installer prints works when pasted from the operator's
  current directory
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

The refusal suggested `./sb install`, but the operator was in `~` and the
binary was `~/statbus/sb`. The triage cites `cli/cmd/install.go:535` and the
installer directory setup at `install.sh:349`; it also calls out another rerun
hint at `install.go:889`.

## Goal

Every rerun hint the installer prints includes the resolved install directory,
for example `cd ~/statbus && STATBUS_MIN_DISK_GB=N ./sb install`, so it works
when pasted into the shell where the operator ran install.sh.

## Done when

- Running install.sh from `~` and pasting the printed hint reruns the install
  successfully.
- The hints at `install.go:535` and `install.go:889` both use the resolved
  directory.
