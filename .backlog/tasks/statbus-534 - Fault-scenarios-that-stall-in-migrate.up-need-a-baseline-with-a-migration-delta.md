---
id: STATBUS-534
title: >-
  Fault scenarios that stall in migrate.up need a baseline with a migration
  delta
status: In Progress
assignee: []
created_date: '2026-10-29T21:50:00Z'
updated_date: '2026-10-29T21:50:00Z'
labels:
  - harness
  - release
dependencies: []
priority: high
type: bug
ordinal: 460204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
v2026.10.5-rc.01 adds no migration over v2026.10.4 (installer fixes only). The LXD fault fleet (run 40948716142) forked 1-boot-concurrent-install from installed-v2026.10.4, so its HEAD install found Migrations already done, migrate.runUp never reached the C10 stall site, and the scenario timed out after 1200s. Its diagnostic blamed the seed, which was not the cause. 3-postswap-worker-ddl-deadlock declares the same precondition and passed without any DDL running. Baseline selection ignored the scenarios' declared need for a real migration delta.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Scenarios whose fault fires inside migrate.up select the newest stable (RC fallback) below the target that lacks at least one of the target's migrations
- [x] #2 lxd_checkpoint_for_scenario forks the same release the scenario selects
- [x] #3 The no-delta diagnostic names the real causes instead of only the seed
- [x] #4 Red/green: new release-baseline and checkpoint-identity assertions fail on the pre-fix tree and pass after
- [ ] #5 The fault fleet passes 1-boot-concurrent-install on the next candidate
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Root cause journaled in tmp/journal.md. Red on pre-fix tree b8a18d41b: release-baseline-test rank_release_baselines_from_tags: command not found (rc=127); lxd-checkpoint-identity-test FAIL: 1-boot-concurrent-install checkpoint = installed-v2099.01.0-standalone-demo (expected installed-v2099.00.0-standalone-demo). Green after: both PASS, real ledger selects v2026.10.3 for v2026.10.5-rc.01 (2 migrations to apply). Related selftests pass: concurrent-install-observation, lxd-snapshot-layers, lxd-smoke-checkpoint, lxd-arc-a-checkpoint, scenario-helper-resolution. Logs: tmp/test-release-baseline-{red,green}.log, tmp/test-checkpoint-identity-{red,green}.log.
<!-- SECTION:NOTES:END -->
