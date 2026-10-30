---
id: STATBUS-191
title: >-
  runner-migration-tail: move seq-logserver + docker-maintenance workflows onto
  the self-hosted runner (last two public-SSH CI consumers)
status: Done
assignee:
  - engineer
created_date: '2026-07-15 07:42'
updated_date: '2026-07-23 18:37'
labels:
  - ci
  - tooling
  - not-install-upgrade
dependencies: []
priority: medium
ordinal: 192000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: zero CI workflows cross niue's public SSH gate — every niue-touching job runs on the self-hosted runner (STATBUS-069's fix), so CrowdSec's community blocklist can never red a gate again.
> CARVED FROM: STATBUS-069 (architect, 2026-07-15, King-prod plan) — the engineer-ready, NOT-King-gated half of the remaining 069 scope; split so it closes independently of the canary provisioning chain.
> COMPLEXITY: engineer, small — the notify/pg_regress/deploy-to-* migrations already shipped and are the pattern; rollback = one runs-on line per workflow (doc-026).

SCOPE: per doc-026's migration order, move the LAST two SSH consumers — the seq-logserver workflow and the docker-maintenance workflow — from hosted runners (public SSH to niue) onto the self-hosted `niue` runner. Same shape as the shipped migrations: runs-on gains the self-hosted labels; the SSH hop to 127.0.0.1/private path per the shipped precedents; NO pull_request-triggered job ever carries self-hosted labels (the doc-026 load-bearing security rule — both these workflows are schedule/push-triggered, verify at build).

ORACLE: both workflows GREEN on the runner on their next natural trigger, and a grep proves zero remaining public-SSH niue consumers in .github/workflows/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 seq-logserver workflow runs-on the self-hosted runner; next natural trigger GREEN
- [x] #2 docker-maintenance workflow runs-on the self-hosted runner; next natural trigger GREEN
- [x] #3 Grep proves zero public-SSH niue consumers remain in .github/workflows/; doc-026 security rule re-verified (no PR-triggered job carries self-hosted labels)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Migrations committed (e26d9b6c5, 2026-07-15). Remaining: AC#1/#2 close on each workflow's next natural trigger running GREEN on the self-hosted runner; AC#3's grep + security-rule re-verification records with the closing note.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-23 16:23
---
AC#1 + AC#2 PROVEN (foreman verification 2026-07-23, prompted by the King's pre-cut review — nothing was holding this ticket back except nobody checking the oracle): both workflows' NATURAL SCHEDULED TRIGGERS fired 2026-07-19 (post-migration commit e26d9b6c5 of 07-15) and ran GREEN ON THE SELF-HOSTED RUNNER — verified via the GitHub API: seq-logserver job 'Upgrade Seq Logging Server' labels self-hosted,niue runner=niue; docker-maintenance job 'Remove obsolete docker artifacts' labels self-hosted,niue runner=niue. AC#3 grep result, precise: (a) fast-tests.yaml's niue mention is a COMMENT only — no SSH; (b) pg_regress.yaml's self-hosted job is gated `if: workflow_dispatch || workflow_run` — never pull_request; the doc-026 security rule HOLDS at job level; (c) ONE real remainder: deploy-via-upgrade.yaml — a workflow_dispatch-ONLY manual deploy tool (target input statbus_<slot>@niue) that would SSH from a HOSTED runner if invoked; superseded in practice by the deploy branches + upgrade service. Disposition routed to the King: retire it (recommended — superseded) or one-line runs-on migration. AC#3 checks on that disposition.
---

author: foreman
created: 2026-07-23 18:37
---
AC#3 COMPLETE — TICKET DONE (2026-07-23): deploy-via-upgrade.yaml RETIRED (a0409d293, King directive — superseded by the deploy branches + upgrade service; it was the last workflow that could SSH niue from a hosted runner, manual-dispatch-only). Final sweep state: fast-tests.yaml's niue mention is a comment; pg_regress's self-hosted job is if-gated to workflow_dispatch/workflow_run (never pull_request) — the doc-026 rule holds at job level; ZERO public-SSH niue consumers remain in .github/workflows/. AC#1/#2 were proven by the 2026-07-19 natural scheduled triggers running green on runner 'niue' (API-verified labels).
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The last two public-SSH CI consumers (seq-logserver, docker-maintenance) moved onto the self-hosted niue runner (e26d9b6c5) and were proven by their natural scheduled triggers running green on the runner (2026-07-19, API-verified). The closing sweep retired the superseded manual deploy-via-upgrade workflow (a0409d293), leaving zero workflows that cross niue's public SSH gate; the doc-026 rule (no PR-triggered job on self-hosted labels) re-verified at job level.
<!-- SECTION:FINAL_SUMMARY:END -->
