---
id: STATBUS-393
title: >-
  When services fail to start, the installer lists every service with its state
  and startup error, stopped ones included
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

A partial compose start can leave app, worker, or rest in Created/Exited state,
which `docker ps` hides. The triage says install has no `docker ps -a` failure
report and cites the all-profile start at `cli/cmd/install.go:1374-1381`.

## Goal

When the Services step fails, the installer prints every compose service with
its state, including Created and Exited ones, and each failed service's startup
error, so the operator sees which component failed and why.

## Done when

- In the Finland shape (port 80 taken), the report shows `proxy` Exited with the
  bind error, and app/worker/rest with their states.
