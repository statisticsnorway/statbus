---
id: STATBUS-394
title: >-
  After migrations, the installer waits for every client service to be ready and
  shows the logs of any that keeps restarting
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

The Finland transcript showed `statbus-local-rest` as `Restarting (1)`. The
triage identifies `cli/internal/compose/compose.go:442` as treating restarting
as not-running, so it is excluded from the resume list and the install gives no
focused log diagnosis.

## Goal

After migrations, the installer waits until every client service (rest,
worker, app) is ready. For a service that keeps restarting or exits, it shows
the service's state and its recent logs.

## Done when

- A healthy install ends with the installer confirming each client service
  ready.
- With rest in `Restarting (1)`, the operator sees rest named, its state, and
  its last log lines.
