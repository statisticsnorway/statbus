---
id: STATBUS-388
title: >-
  Migration connection failures must identify the missing Caddy proxy and database port
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

Migrations reported only `dial tcp 127.0.0.1:5431: connection refused` after
the proxy failed to start. The triage points to `cli/internal/migrate/migrate.go:957`
and explains that standalone port 5431 is published only by the proxy. The
operator therefore saw a database-looking error instead of the missing service.

## Done when

The migration and host-psql connection paths report that CADDY_DB_PORT is
published by the proxy, include its observed state, and point to the relevant
container logs.
