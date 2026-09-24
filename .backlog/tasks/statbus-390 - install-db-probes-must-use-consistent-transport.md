---
id: STATBUS-390
title: >-
  Install database probes must use the same transport as migrations
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

Seed checking can bypass the failed proxy with `docker compose exec -T db psql`,
while migrations use TCP through 127.0.0.1:5431. The mismatch is documented in
the triage at `cli/cmd/install.go:2329-2371` versus
`cli/internal/migrate/migrate.go:919-923`, allowing install to pass an earlier
probe and fail later on the proxy.

## Done when

All install-time database readiness checks use one explicit transport, or both
paths require and diagnose the proxy consistently.
