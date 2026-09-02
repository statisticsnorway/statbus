---
id: STATBUS-343
title: >-
  ci-verdict-ledger: workflow completions recorded where a git fetch can read
  them — the end of REST polling
status: To Do
assignee: []
created_date: '2026-09-02 12:43'
labels:
  - release
  - ops
  - resilience
dependencies: []
priority: medium
type: enhancement
ordinal: 336000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today's rate-limit incident (the foreman's watchers + preflights burned the GitHub REST quota and blocked the rc.03 cut on HTTP 403) motivates replacing poll-the-API with record-the-verdict.

The event exists: GitHub fires workflow_run completion. Missing is only a durable, cheaply-readable place it lands.

Design candidates for the King's ruling:
A. (recommended) GitHub-native verdict ledger: a workflow_run-triggered workflow in the repo appends {sha, workflow, conclusion, run_id, finished_at} to a dedicated git ref (e.g. refs/ci-verdicts — an orphan branch or notes ref). Readers do one git fetch of that ref — smart-HTTP, no REST quota, the transport every box already uses. Release preflight's five REST checks become one fetch + local reads; watchers poll a ref for pennies. Matches the commit-is-authoritative doctrine: the ledger IS the repo. No new hosts, secrets, or daemons.
B. Receiver on niue: webhook endpoint appending to a file/table, read over SSH. No REST in the read path, but adds a webhook secret + a daemon to operate.
C. Do nothing structural; keep the polite-cadence polling discipline (recorded in tmp/rc-cut-procedure.md).

Scope note: this serves OUR release machinery; customer boxes are untouched (their discovery already uses git transport). The Slack UPGRADE_CALLBACK stays as human notification; this is the machine-readable sibling.

Acceptance (post-ruling, for A): every workflow_run completion lands in the ledger within a minute; ./sb release preflight reads verdicts from the ledger with REST as fallback only; watchers documented to poll the ledger; one release cut end-to-end with zero REST status calls.
<!-- SECTION:DESCRIPTION:END -->
