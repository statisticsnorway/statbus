---
id: STATBUS-593
title: Remediate currently open application dependency security advisories
status: In Progress
assignee: []
created_date: '2026-11-08T10:21:00Z'
updated_date: '2026-11-08T10:40:00Z'
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
- [x] #1 Record current advisory IDs, affected installed versions, fixed-version ranges and runtime or tooling reachability using primary advisory evidence.
- [x] #2 Apply the smallest compatible dependency fixes and verify resolved lockfile versions, without ignoring alerts or forcing unreviewed major API changes.
- [x] #3 Relevant sanitization, validation, HTTP and diagram behavior tests plus full frontend typecheck, lint, tests and build pass on the resulting dependency graph.
- [ ] #4 Record exact committed source CI status and any remaining advisory with an evidence-based mitigation or explicit owner review gate before a future stable release.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Coordinator verification 2026-11-08 10:40 UTC: compatible fixes and primary advisory/reachability ledger are in doc/security-dependency-review-20261108.md. Dependency regressions reproduced real SRI and sanitizer defects before patch. Query-array guard RED11/16 then GREEN16/16, root independently passed21 actual parser/security tests. Full frontend final27suites229tests/typecheck/lint0errors5warnings/productionbuild pass. Compatible graph audit has0critical but1high,3moderate,2low (five unique advisory IDs), not all-clear. Zod query arrays are bounded before JSON.parse and all root/nested Zod traversal, but vendor vulnerability remains unpatched. Residual runtime/major/no-fix review gates remain explicit and next stable is HARD HELD for owner approval. Original security commits211519497/76413f1f8 map unchanged to f7abff119/7841df985 at integrated source7841df9852f2f5bf84d64ee8132c523306f6f328. AC4 remains unchecked pending exact integrated CI and evidence. No alert dismissed or deployed.
<!-- SECTION:NOTES:END -->
