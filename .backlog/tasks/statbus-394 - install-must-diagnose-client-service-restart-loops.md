---
id: STATBUS-394
title: >-
  Install must diagnose client services that remain in a restart loop
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

The Finland transcript showed `statbus-local-rest` as `Restarting (1)`. The
triage identifies `cli/internal/compose/compose.go:442` as treating restarting
as not-running, so it is excluded from the resume list and the install gives no
focused log diagnosis.

## Done when

After migrations, install waits for every client service to become ready and
prints recent logs plus state for any service that remains restarting or exits.
