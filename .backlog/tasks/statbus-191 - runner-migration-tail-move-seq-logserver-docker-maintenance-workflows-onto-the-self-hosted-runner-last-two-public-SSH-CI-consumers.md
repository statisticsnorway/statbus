---
id: STATBUS-191
title: >-
  runner-migration-tail: move seq-logserver + docker-maintenance workflows onto
  the self-hosted runner (last two public-SSH CI consumers)
status: To Do
assignee:
  - engineer
created_date: '2026-07-15 07:42'
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
- [ ] #1 seq-logserver workflow runs-on the self-hosted runner; next natural trigger GREEN
- [ ] #2 docker-maintenance workflow runs-on the self-hosted runner; next natural trigger GREEN
- [ ] #3 Grep proves zero public-SSH niue consumers remain in .github/workflows/; doc-026 security rule re-verified (no PR-triggered job carries self-hosted labels)
<!-- AC:END -->
