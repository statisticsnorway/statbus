---
id: STATBUS-593
title: Remediate currently open application dependency security advisories
status: In Progress
assignee: []
created_date: '2026-11-08T10:21:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 509204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Read-only GitHub advisory inspection on 2026-11-08 confirms 23 open npm dependency alerts, including five critical alerts. Historic Done tasks 448 and 363 do not cover the current versions. These are pre-existing application dependencies, not a demonstrated 591 regression. Remediate compatible fixes with positive application checks and document any unavailable fix or compatibility gate explicitly. Next stable remains held for owner review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Record current advisory IDs, affected installed versions, fixed-version ranges and runtime or tooling reachability using primary advisory evidence.
- [ ] #2 Apply the smallest compatible dependency fixes and verify resolved lockfile versions, without ignoring alerts or forcing unreviewed major API changes.
- [ ] #3 Relevant sanitization, validation, HTTP and diagram behavior tests plus full frontend typecheck, lint, tests and build pass on the resulting dependency graph.
- [ ] #4 Record exact committed source CI status and any remaining advisory with an evidence-based mitigation or explicit owner review gate before a future stable release.
<!-- AC:END -->
