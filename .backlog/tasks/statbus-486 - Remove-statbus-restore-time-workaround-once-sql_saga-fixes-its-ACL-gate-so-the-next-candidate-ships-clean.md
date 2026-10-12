---
id: STATBUS-486
title: >-
  Remove statbus restore-time workaround once sql_saga fixes its ACL gate, so
  the next candidate ships clean
status: To Do
assignee: []
created_date: '2026-10-12 19:31'
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
- [ ] #1 With the fixed sql_saga installed, a dump restore round-trips cleanly WITHOUT setting session_replication_role, in both a serial restore and pg_restore -j 4, proven by the same checks that require the suppression today (cli/cmd/restore_replica_test.go, the seed round-trip guard, and the seed step in Fast Tests)
- [ ] #2 The suppression is removed from statbuss restore path (cli/cmd/restore_replica.go and its callers in db.go and seed.go), and the full fast suite plus Go Test are green without it at job level
- [ ] #3 The seed round-trip guard and migration 20261008183553 (481-B) are deliberately retained, with the reason recorded in the ticket
- [ ] #4 The candidate register step cites both this ticket and STATBUS-482 as satisfied before the next tag is pushed, so no candidate ships with the workaround present
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The removal commit names the upstream commit it depends on, and the release candidate that follows records both this ticket and STATBUS-482 as Done
- [ ] #2 The ticket states what was removed, what was kept, and the observed restore evidence without the suppression
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed 2026-10-12 on the owners instruction to record clearly that plan option B (cut the candidate first) is waiting on sql_saga. Owner is following up sql_saga through another agent; STATBUS-482 holds the upstream design and review. Do not start the removal before the upstream fix is in.
<!-- SECTION:NOTES:END -->
