---
id: STATBUS-384
title: >-
  Install Services step must verify every required service, not only a healthy database
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

On Ville-Mattis Pilvio's Ubuntu 26.04 install, Apache held port 80, so the first
`docker compose --profile all up -d` left the Caddy `proxy` container stopped.
On rerun, the Services step was accepted because the database was healthy, and
the proxy was never retried. Migrations then failed because nothing published
127.0.0.1:5431. The triage records this at `cli/cmd/install.go:1058-1079`
(`checkServicesDone` checks only `compose ps db`) and `cli/cmd/install.go:1374-1381`
(the initial all-profile start).

## Done when

The Services check requires every service needed by the selected mode/profile to
be running and healthy, or the installer reruns the idempotent start operation.
A regression test covers a healthy DB with a stopped proxy.
