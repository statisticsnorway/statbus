---
id: STATBUS-188
title: >-
  dev-db-crash-cycles: straggler kill -9 remediation correlates with postmaster
  crash recovery; crash-notice log lines missing
status: To Do
assignee: []
created_date: '2026-07-14 23:17'
labels:
  - testing
  - infrastructure
  - not-install-upgrade
dependencies: []
priority: medium
ordinal: 189000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the dev harness's own straggler remediation must never destabilize the shared dev database, and every postgres crash must leave its root-event evidence in reachable logs.

OBSERVED (2026-07-14 22:06-23:14 UTC, local dev db, container statbus-local-db Up 39h): THREE postgres crash-recovery cycles (22:06→22:24, 22:43→22:44, 23:14) during STATBUS-175 batch work. Initial read was macOS Docker memory pressure under heavy 401 import load. The third cycle sharpened it: mechanic's kill -9 on straggler pg_regress+psql PIDs (dev.sh's OWN documented remediation, via docker compose exec db) was followed within ~30s by recovery mode — 2-for-2 across incidents. Killing a pure CLIENT psql cannot cause postmaster crash recovery (backend sees EOF, aborts cleanly); only a BACKEND death can. Hypotheses: (a) PID reuse between pgrep and kill catching a backend; (b) the pgrep pattern ('pg_regress|HIDE_TABLEAM') matching more than clients; (c) coincidental OS/VM OOM kill of the import backend at cleanup time (Docker VM 15.6GiB).

SECOND ANOMALY: across the container's ENTIRE docker-log history there is NO 'server process was terminated by signal' / 'crash of another server process' line — postgres's standard crash-detection evidence is absent despite three recovery cycles, and the in-container collector file (/var/log/postgresql/postgresql-18-main.log) is EMPTY (0 lines). The postmaster's own log stream apparently goes nowhere reachable. Root-cause diagnosis is impossible without it.

CHAIN-STARTER, also in scope: 401's regeneration ran ~28 min and was killed by the runner's background-task timeout, leaving the straggler — recurring by construction for any test longer than the runner budget.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Postmaster log stream made reachable (crash-notice lines land in docker logs or a non-empty collector file) — no future crash without root-event evidence
- [ ] #2 The kill-then-recovery causality resolved with evidence (exact killed cmdlines / PID-reuse check / OOM evidence from the Docker VM), not pattern-matching
- [ ] #3 dev.sh straggler remediation re-ruled if implicated: safe kill order/signal (TERM to clients first, never blind -9 in the db container) documented in the BLOCKED-lock message
- [ ] #4 Long-test regeneration path documented so runner timeouts stop manufacturing stragglers (adequate timeout or detached run for 400/401-class tests)
<!-- AC:END -->
