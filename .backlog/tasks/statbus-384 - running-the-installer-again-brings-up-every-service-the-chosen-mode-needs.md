---
id: STATBUS-384
title: Running the installer again brings up every service the chosen mode needs
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

On Ville-Mattis Pilvio's Ubuntu 26.04 install, Apache held port 80, so the first
`docker compose --profile all up -d` left the Caddy `proxy` container stopped.
On rerun, the Services step was accepted because the database was healthy, and
the proxy was never retried. Migrations then failed because nothing published
127.0.0.1:5431. The triage records this at `cli/cmd/install.go:1058-1079`
(`checkServicesDone` checks only `compose ps db`) and `cli/cmd/install.go:1374-1381`
(the initial all-profile start).

## Goal

A rerun of `./sb install` looks at every service the chosen mode needs (db,
proxy, rest, worker, app) and starts whichever is not running, so the install
finishes with the whole stack up.

## Done when

- A rerun after a partial start ends with every service of the selected mode
  running and healthy.
- The Services step counts as done only when all of those services are running;
  otherwise it runs the idempotent start again.
- A regression test starts from a healthy db with a stopped proxy and observes
  the rerun bring the proxy up and migrations succeed.
