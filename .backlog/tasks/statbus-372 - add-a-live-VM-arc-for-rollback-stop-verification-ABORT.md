---
id: STATBUS-372
title: >-
  add a live VM arc for rollback stop-verification ABORT when a serving service
  refuses to stop
status: To Do
assignee: []
created_date: '2026-09-17 10:10'
updated_date: '2026-09-17 10:10'
labels:
  - release
  - upgrade
  - recovery
  - testing
dependencies: []
priority: high
type: task
ordinal: 1
---

## Coverage gap (rc.17 RCA, 2026-09-17)

The `StartDBForRecovery` caller audit in `tmp/rc17-rca.md` found no named live
VM arc for caller 4, the rollback stop-verification ABORT path in `service.go`.
This branch is entered when `docker compose stop` or `VerifyStopped` cannot prove
the serving tier stopped. One of app, worker, or rest may therefore be live by
definition. Database-route startup must permit that state long enough to write
the durable `ROLLBACK_FAILED_SERVICES_NOT_STOPPED` terminal; it must not run the
held-closed verifier, restore the snapshot/source, or start the full stack.

Unit/source coverage exists in `rollback_abort_dbstart_test.go`,
`rollback_schema_floor_failclosed_test.go`, and the rc.17 caller-contract tests.
That is not a live proof that a real serving container refusing to stop reaches
and records the intended terminal.

## Done when

A named install-recovery VM arc makes one serving service refuse to stop, proves
the product takes the rollback stop-verification ABORT branch, and asserts:

1. database plus the existing proxy route can start so the terminal write lands;
2. the row records `ROLLBACK_FAILED_SERVICES_NOT_STOPPED` with truthful degraded
   narration;
3. no snapshot/source restore runs and no full-stack startup occurs;
4. the held-closed verifier is not applied to this route-only caller; and
5. the box and retained recovery evidence remain operable for the documented
   human response.
