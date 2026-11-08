---
id: STATBUS-592
title: Release discovery succeeds when another fetch updates the same remote ref
status: In Progress
assignee: []
created_date: '2026-11-08T09:27:00Z'
updated_date: '2026-11-08T09:44:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 508204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Poststable fixture commit e1842180ab7b8d56ec80ce332ee8ef2a28c29c8a hit an actual dev notification failure: git fetch --tags could not lock refs/remotes/origin/master because another fetch had already advanced it from 571336064 to e1842180a. Release42466579628 and stable v2026.11.2 remain successful and unchanged. Reproduce the competing-fetch outcome without mutating any deployment, then make release discovery converge under bounded handling while preserving credential, pruning, moved-tag and unexpected-error contracts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A deterministic behavioral regression reproduces competing fetch reference advancement and shows discovery returning the actual release tags after convergence.
- [x] #2 Bounded handling preserves immediate or bounded explicit failure for persistent reference contention, authentication errors and moved-tag conflicts, and existing discovery tests pass.
- [ ] #3 Relevant CLI regression and exact-SHA CI pass; the failed original notification is rechecked with explicit status and conclusion and deployment state remains truthful.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Actual failed run42467077078/job128688996201 at2026-11-08T09:25:16Z. Complete failed log saved tmp/stable-config-notify-failure.log. Stable production target929fe787 is not altered by this followthrough.

2026-11-08 09:39 UTC: actual real-Git competing-ref regression RED c20589aa2, GREEN0bd46a553, staticcheck predicate followup d23cb4409f413b47558ef2ea019b9f1612e27858 pushed. Reference-transaction hook deterministically reproduces origin/master expected-old mismatch. Tests verify actual discovered remote tag/SHA and pruning, transient/persistent owned lock handling (two bounded waits, original lock preserved), concurrent identical tag convergence, moved-tag immediate rejection despite simultaneous lock contention, and existing auth/rate-limit behavior. Full upgrade suite139.212s; focused tests five repeated runs; root independent final race3.943s, actual golangci-lint0issues. Original notify42467077078 attempt1 preserved and diagnosed; attempt2completed/success09:28. Dev/Norway monitors healthy rc04,0failed. Stablev2026.11.2 remains unchanged929fe787 and published. Exact new source CI still pending, no deployment proof or released fix claimed.

2026-11-08 09:44 UTC: d23cb4409 Go42468112418, Images42468112415, app42468112411 and Notify42468112428 completed/success. Managed GitHub dynamic CodeQL run42468112184 failed only downloading Python CLI bundle2.27.4 (HTTP504 after retries), before analysis; Go, actions and JavaScript/TypeScript analyses passed. GitHub explicitly refuses rerun of this dynamic workflow. Failed job log/JSON preserved tmp/592-push-ci-failure.log/.json, no bypass or false-green claim. Relevant tests/Harness/Fast continue. This evidence commit preserves active acceptance gap and causes normal next-SHA CI, including managed CodeQL, without changing product source. Fixture e184 all exactCI now completed/success including Fast42467346487.
<!-- SECTION:NOTES:END -->
