---
id: STATBUS-390
title: >-
  Every install-time database check reaches the database the same way migrations
  do
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

Seed checking can bypass the failed proxy with `docker compose exec -T db psql`,
while migrations use TCP through 127.0.0.1:5431. The mismatch is documented in
the triage at `cli/cmd/install.go:2329-2371` versus
`cli/internal/migrate/migrate.go:919-923`, allowing install to pass an earlier
probe and fail later on the proxy.

## Goal

Every install-time database check reaches the database by the same path
migrations use, so a check that passes means migrations can connect too.

## Done when

- Seed checking and migrations use one named transport.
- With the proxy stopped, the first database check reports the proxy (per
  STATBUS-388), at the same step migrations would.
