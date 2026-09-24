---
id: STATBUS-393
title: >-
  Install failure diagnostics must report Created and Exited compose services
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

A partial compose start can leave app, worker, or rest in Created/Exited state,
which `docker ps` hides. The triage says install has no `docker ps -a` failure
report and cites the all-profile start at `cli/cmd/install.go:1374-1381`.

## Done when

A Services failure prints compose status including stopped containers and the
per-service startup error, so the operator can identify the failed component.
