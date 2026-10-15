---
id: STATBUS-486
title: >-
  Remove statbus restore-time workaround once sql_saga fixes its ACL gate, so
  the next candidate ships clean
status: Done
assignee: []
created_date: '2026-10-12 19:31'
updated_date: '2026-10-15 23:54'
labels:
  - release
  - upgrade
  - sql_saga
dependencies: []
priority: high
type: task
ordinal: 412204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BLOCKING RELATIONSHIP, recorded here because it gates the release path: the next release candidate is blocked on TWO things, in this order. (1) The upstream sql_saga fix, tracked in STATBUS-482 by the owner and being followed up with another agent. (2) This ticket. Until both are done, statbus still carries a local workaround for the sql_saga ACL defect, and the owner ruled that no candidate is cut on a ship carrying it. B (the release observation of 460 and 475 on dev) waits on both; plan A, agreed 2026-10-12, is machinery first, so the candidate follows the removal rather than preceding it.

WHAT THE WORKAROUND IS, grounded:
- 3ce591f16, "cli: restore dumps with event triggers suppressed, and prove the seed round-trips (STATBUS-481 C+D)": statbus restores a dump with session_replication_role = replica so sql_saga health_checks cannot fire on the transient states pg_restore passes through, and it added a seed round-trip guard to prove the restore is faithful. Files: cli/cmd/restore_replica.go, cli/cmd/db.go, cli/cmd/seed.go, cli/cmd/seed_build.go, cli/cmd/seed_roundtrip.go, cli/cmd/seed_verify.go.
- 524669e21, "sql: sql_saga for-portion-of views carry their tables ACL (STATBUS-481 B)": migration 20261008183553_statbus_481_for_portion_of_views_carry_their_table_acl, a released data repair for boxes whose view ACLs had diverged. It also sets session_replication_role = replica inside its own transaction.

WHY THE SUPPRESSION CAN GO, and only after the fix: the adversarial review in STATBUS-482 (tmp/design_a_review.md, amendment 3) found that accepting the derived-object check when the base ACL is NULL is what makes serial AND parallel restore work without a suppression GUC and without weakening live protection. So the suppression is the workaround, and the upstream fix is the replacement.

WHAT MUST NOT BE REMOVED: the seed round-trip guard (a guard, not a workaround: it proves the restore is faithful) and the 481-B repair migration (a released forward migration that fixed real boxes; released migrations are immutable).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With the fixed sql_saga installed, a dump restore round-trips cleanly WITHOUT setting session_replication_role, in both a serial restore and pg_restore -j 4, proven by the same checks that require the suppression today (cli/cmd/restore_replica_test.go, the seed round-trip guard, and the seed step in Fast Tests)
- [x] #2 The suppression is removed from statbuss restore path (cli/cmd/restore_replica.go and its callers in db.go and seed.go), and the full fast suite plus Go Test are green without it at job level
- [x] #3 The seed round-trip guard and migration 20261008183553 (481-B) are deliberately retained, with the reason recorded in the ticket
- [x] #4 The candidate register step cites both this ticket and STATBUS-482 as satisfied before the next tag is pushed, so no candidate ships with the workaround present
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The removal commit names the upstream commit it depends on, and the release candidate that follows records both this ticket and STATBUS-482 as Done
- [x] #2 The ticket states what was removed, what was kept, and the observed restore evidence without the suppression
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed 2026-10-12 on the owners instruction to record clearly that plan option B (cut the candidate first) is waiting on sql_saga. Owner is following up sql_saga through another agent; STATBUS-482 holds the upstream design and review. Do not start the removal before the upstream fix is in.

PREPARED 2026-10-13 (coordinator, read-only inventory). The whole suppression is ONE helper plus six call sites, all under cli/cmd: helper restoreTargetConninfo at cli/cmd/restore_replica.go:36 (returns dbname plus options='-c session_replication_role=replica'); call sites db.go:790 (phase 1 pre-data), db.go:819 (phase 2.5 auth.user list), db.go:853 (phase 3 data+post-data+ACLs), seed.go:319 (seed restore with --disable-triggers), seed_build.go:212 (--single-transaction), seed_verify.go:485 (--single-transaction); unit test restore_replica_test.go:15. WHEN THE sql_saga FIX IS IN: replace each call with the plain quoted dbname (the helper's only other job is quoting dbName for the conninfo grammar, so keep that half), delete restore_replica.go and restore_replica_test.go, then run the restore round-trip WITHOUT session_replication_role in both serial and pg_restore -j 4 (AC#1), the fast suite plus Go Test at job level (AC#2). KEEP: verifySeedRoundTrip and migration 20261008183553_statbus_481_for_portion_of_views_carry_their_table_acl (AC#3). Before pushing the tag, register the candidate citing 486 and STATBUS-482 as satisfied (AC#4). Blocked on: the upstream sql_saga ACL-gate fix via STATBUS-482; the owner is following that up.

OWNER DECISION 2026-10-14: the upstream sql_saga ACL-gate fix (STATBUS-482) did NOT land, and v2026.10.1-rc.01 was cut anyway because the Uganda box is waiting. CONSEQUENCE, recorded so the ticket does not pretend otherwise: this candidate SHIPS WITH the restore-time suppression, so AC#4 ('no candidate ships with the workaround present') is knowingly NOT met by v2026.10.1-rc.01. The suppression inventory above is unaffected: when the fix does land, this ticket's job is unchanged - swap the six call sites, delete restore_replica.go and its test, prove the round trip without session_replication_role in serial and pg_restore -j 4, keep verifySeedRoundTrip and migration 20261008183553.

### Done through STATBUS-511 (42739f5f9, 2026-10-15)
sql_saga v1.1 shipped the ACL-gate fix. The suppression is removed from every restore path (restore_replica.go and its six call sites), with the seed round trip passing without it and test 352 retired. The seed round-trip guard and migration 20261008183553 are kept (reasons on STATBUS-511). Closes with 511 once CI and the next candidate are green.

### CI green (2026-10-15)
CI on 42739f5f9 at job level: Images 38794026480 success (db image amd64+arm64 with sql_saga v1.1; seed job round trip without suppression: ACL digest identical, event triggers 7/7, types equal), Go Test 38794026570 success (go test + golangci-lint), Harness Selftest 38794026593 success, app build & lint 38794026656 success. Fast Tests 38802563803 success (pg_regress fast suite) at 3380e9ac0, which contains 42739f5f9 with identical suite inputs (migrations, test, cli, postgres, dev.sh, app/src/lib); the runs at 42739f5f9 itself were cancelled by later pushes. Closes with STATBUS-511 after the next candidate's ladder.

### Closed 2026-10-16
Removed: restoreTargetConninfo (session_replication_role=replica) at all six restore call sites and test 352 (42739f5f9, sql_saga v1.1). Kept: the seed round-trip guard (now proving restores with checks active) and migration 20261008183553 (released). Restore evidence without the suppression: local seed build and CI's seed job both report the round trip OK with event triggers 7/7. v2026.10.2-rc.01 (840d3970c) ladder, all green at job level: Release 38818198739 (15/15), Test Hardening 38818198673 (3/3), Fast Tests 38818198705, Test Smoke 38818339306 (5/5), dev canary 38819635051 (2/2, dev reports v2026.10.2-rc.01), LXD Fork Fleet 38819807364 STATUS=PASSED 27/27 scenarios PASS, Upgrade Arc Harness 38819893048 (41 success, 1 skipped), Release Fleet Orchestrator 38818198690 success. Done.
<!-- SECTION:NOTES:END -->
