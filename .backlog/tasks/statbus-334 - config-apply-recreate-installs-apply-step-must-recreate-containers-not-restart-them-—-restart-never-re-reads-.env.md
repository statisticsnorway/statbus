---
id: STATBUS-334
title: >-
  config-apply-recreate: install's apply step must recreate containers, not
  restart them — restart never re-reads .env
status: To Do
assignee: []
created_date: '2026-09-01 20:47'
labels:
  - cli
  - config
  - ops
  - defect
dependencies: []
priority: high
type: bug
ordinal: 327000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Issue: ./sb install's "Apply config changes" step (STATBUS-332) runs `docker compose restart <service>` (cli/cmd/install.go:1348-1356).
Docker restart reuses the container's creation-time config and never re-reads .env interpolation.
Proven empirically 2026-09-01 on the local box: with VERSION changed in .env, `docker compose restart worker` kept the old value; `docker compose up -d worker` recreated and picked up the new one.
All five services receive config via compose `environment:` interpolation (no env_file anywhere), so every Docker restart class is affected.
The step therefore detects a change, restarts the service, and silently does not apply it — the exact failure 332 existed to end.

Fix: change composeRestart's command from `docker compose restart <service>` to `docker compose up -d --no-deps <service>`.
--no-deps preserves the per-class isolation (no dependency cascade).
Update the step's wording, errors, and the restart-class tests from restart to recreate.
RestartUpgradeDaemon (host systemd) is unaffected.

Acceptance: a changed generated key of each Docker class, applied via ./sb install, is observable inside the recreated container (printenv); the no-change-no-restart test still passes; existing 332 structural pins updated and green.
<!-- SECTION:DESCRIPTION:END -->
