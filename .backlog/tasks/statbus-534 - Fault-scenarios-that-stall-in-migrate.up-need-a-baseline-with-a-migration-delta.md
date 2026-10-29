---
id: STATBUS-534
title: >-
  Fault scenarios that stall in migrate.up need a baseline with a migration
  delta
status: In Progress
assignee: []
created_date: '2026-10-29T21:50:00Z'
updated_date: '2026-10-29T23:27:00Z'
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
- [x] #1 test/install-recovery/tests/release-baseline-test.sh passes the assertion that select_release_baseline_with_migration_delta_from_repo returns v2026.10.3 for v2026.10.5-rc.01, from both the repo root and a subdirectory path
- [x] #2 test/install-recovery/tests/lxd-checkpoint-identity-test.sh passes: 1-boot-concurrent-install resolves installed-<newest release with a delta>-standalone-demo, matching the scenario's own selection
- [x] #3 When Migrations is already done, 1-boot-concurrent-install's stderr says Migrations had nothing to apply and names both causes (no delta from the baseline, or a seed already at the target)
- [x] #4 Both harness tests fail on the pre-fix tree and pass after (logs in tmp/)
- [ ] #5 In the next RC's LXD fleet, 1-boot-concurrent-install and 3-postswap-worker-ddl-deadlock PASS from a baseline with a migration delta
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Root cause journaled in tmp/journal.md. Red on pre-fix tree b8a18d41b: release-baseline-test rank_release_baselines_from_tags: command not found (rc=127); lxd-checkpoint-identity-test FAIL: 1-boot-concurrent-install checkpoint = installed-v2099.01.0-standalone-demo (expected installed-v2099.00.0-standalone-demo). Green after: both PASS, real ledger selects v2026.10.3 for v2026.10.5-rc.01 (2 migrations to apply). Related selftests pass: concurrent-install-observation, lxd-snapshot-layers, lxd-smoke-checkpoint, lxd-arc-a-checkpoint, scenario-helper-resolution. Logs: tmp/test-release-baseline-{red,green}.log, tmp/test-checkpoint-identity-{red,green}.log.

rc.02 LXD fleet run 40966933047: the selector found no delta for ANY release because the scenario runs from the fleet's shadow tree (REPO is a subdirectory) and git diff resolved the 'migrations/*.up.sql' pathspec relative to it. Fixed with ':(top)migrations/*.up.sql'. New release-baseline assertion with REPO_ROOT/test/install-recovery: red on pre-fix tree (got ''), green after (v2026.10.3). Logs tmp/test-release-baseline-subdir-{red,green}.log.
<!-- SECTION:NOTES:END -->
