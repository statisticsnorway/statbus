---
id: STATBUS-536
title: >-
  Upgrade arcs read a rollback's pending-finish 'failed' row as a terminal
  failure
status: In Progress
assignee: []
created_date: '2026-10-30T00:57:00Z'
updated_date: '2026-10-30T01:22:00Z'
labels:
  - harness
  - release
dependencies: []
priority: high
type: bug
ordinal: 462204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
An arc verdict reflects the product's terminal state, never a designed intermediate the poll happened to land on.

### Zoom out
A rollback writes state='failed' with rollback_finish_pending_at set (LabelFailedRollbackPendingFinish), then moves the row to rolled_back once the lock is released. arc_to in arc-helpers.sh already waits through that window (the rc.09 lesson). About 25 arcs and scenarios defined their own state readers with bare `state`, so any of them could break on the intermediate when its poll landed there.

### Zoom in
v2026.10.5-rc.03 Upgrade Arc Harness run 40977271679, job 123810110780 (postswap-rollback-restore-watchdog). The row went failed (pending) to rolled_back within 00:36:27. The arc's 5-second poll read 'failed' and failed the gate, while the final row state was rolled_back. The product behaved correctly.

### Closing review
- **Memory:** none. **Documentation:** UPGRADE_ROW_STATE_SQL in test/install-recovery/lib/assertions.sh states the rule at its definition. **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 test/install-recovery/tests/arc-row-state-pending-finish-test.sh passes: the real arc row_state reads a failed row with rollback_finish_pending_at as finishing_rollback (arc keeps waiting), a plain failed row as failed, a rolled_back row as rolled_back
- [x] #2 Every upgrade-state read in test/install-recovery (35 sites) selects UPGRADE_ROW_STATE_SQL; rg for 'SELECT state FROM public.upgrade' in arcs, lib and scenarios returns only the single-quoted orphaned-volume scenario read
- [x] #3 The test fails on the pre-fix arc (row_state='failed') and passes after; it runs in Fast Tests against the live database with skipping disabled
- [ ] #4 The next RC's Upgrade Arc Harness passes postswap-rollback-restore-watchdog and every other arc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Red on pre-fix arc: 'FAIL: rollback with final transition pending: row_state=failed, want finishing_rollback' (tmp/test-arc-row-state-red.log). Green after (tmp/test-arc-row-state-green.log). 35 state reads in 31 files now select UPGRADE_ROW_STATE_SQL. Offline arc selftests (arc-state-assertions, arc-wait-unit-active, arc-crollback-version-guard, arc-fingerprint-path-scope, lxd-arc-verdict, lxd-arc-lineage-parity, lxd-arc-base-identity, concurrent-install-observation, scenario-helper-resolution, c-rollback-resurrection-fixture, rc10-schema-floor-family) all pass.

Fast Tests run 40983372897 failed the new step: the job's app DB is never migrated ('relation public.upgrade does not exist'). The test now clones POSTGRES_SEED_DB (built at HEAD by migrate-and-test) into a throwaway arc_row_state_<pid> DB, asserts public.upgrade exists, and drops it on exit. Re-verified: red on b29876300's arc (row_state='failed'), green now (tmp/test-arc-row-state-{red2,green2}.log); no scratch DB left behind.
<!-- SECTION:NOTES:END -->
