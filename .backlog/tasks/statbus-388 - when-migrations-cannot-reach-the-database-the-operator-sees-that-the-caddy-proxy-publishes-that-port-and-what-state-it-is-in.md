---
id: STATBUS-388
title: >-
  When migrations cannot reach the database, the operator sees that the Caddy
  proxy publishes that port and what state it is in
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

Migrations reported only `dial tcp 127.0.0.1:5431: connection refused` after
the proxy failed to start. The triage points to `cli/internal/migrate/migrate.go:957`
and explains that standalone port 5431 is published only by the proxy. The
operator therefore saw a database-looking error instead of the missing service.

## Goal

When migrations or host `psql` cannot connect, the message explains that
CADDY_DB_PORT is published by the Caddy proxy, shows the proxy's current state,
and gives the command to read its logs.

## Done when

- With the proxy stopped, the operator sees the proxy named as the cause, its
  state (e.g. Exited), and `./sb logs proxy`.
- With the proxy running, connection errors are reported as before.
