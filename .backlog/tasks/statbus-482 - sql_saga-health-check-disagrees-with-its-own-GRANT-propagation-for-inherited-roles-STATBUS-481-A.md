---
id: STATBUS-482
title: >-
  sql_saga health check disagrees with its own GRANT propagation for inherited
  roles (STATBUS-481 A)
status: To Do
assignee: []
created_date: '2026-10-08 19:24'
updated_date: '2026-10-08 19:44'
labels:
  - sql_saga
  - sql
  - security
dependencies: []
priority: medium
ordinal: 408204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: sql_saga's privilege health check accepts every state its own GRANT propagation produces, so no database can reach a state where an unrelated REVOKE anywhere raises. CONTEXT: STATBUS-481 traced an unrestorable dump and a live REVOKE failure to sql_saga.health_checks (event trigger on ddl_command_end), source veridit/sql_saga src/2h_health_checks.sql, pinned in statbus at sql_saga_release=9e39fcc (postgres/Dockerfile). The GRANT-propagation branch ('Propagate GRANTs to for-portion-of views') uses has_table_privilege(grantee, view, privilege), which is INHERITANCE-AWARE: admin_user inherits regular_user, so a GRANT to admin_user on a base table is never copied to its __for_portion_of_valid view. The REVOKE-check branch ('Check REVOKEs on for-portion-of views') compares EXACT aclexplode entries of table and view. The two disagree for inherited roles, so the state propagation produces fails the check. Because sql_saga.__internal_ddl_command_affects_managed_object returns true for every GRANT/REVOKE (objid unreliable), the check runs on unrelated REVOKEs too; on master before STATBUS-481 B, 'REVOKE ALL ON FUNCTION public.upgrade_schedule(text, boolean) FROM PUBLIC' raised 'cannot revoke INSERT directly from activity__for_portion_of_valid'. STATBUS-481 repaired statbus without changing sql_saga: B (migration 20261008183553) makes every view's ACL equal its table's, and C (3ce591f16) restores dumps with session_replication_role=replica so a dump replay's transient states are not checked. This ticket prevents the class at its source. SHAPE OPTIONS (owner decides): (1) make the REVOKE/GRANT checks inheritance-aware like the propagation they verify (has_table_privilege on the view), or (2) make the propagation exact (aclexplode equality, so admin_user is copied even though it inherits), optionally (3) limit the check to objects the GRANT/REVOKE actually touched. Any choice requires a sql_saga release and bumping sql_saga_release in postgres/Dockerfile.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The owner has chosen the shape (inheritance-aware check, or exact propagation) and it is recorded here
- [ ] #2 sql_saga's own test suite covers an inherited role: GRANT on a base table to a role that inherits another grantee, then an unrelated REVOKE succeeds
- [ ] #3 statbus pins the new sql_saga release in postgres/Dockerfile and test 352 still passes (view ACL = table ACL; an unrelated REVOKE succeeds; a REVOKE that breaks a view ACL is still refused)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROOT CAUSE PINNED TO LINES, and this is the owner's own extension (author: the owner; local clone /Users/jhf/ssb/sql_saga at the pinned 9e39fcc, which is HEAD there). Two defects in src/, so the fix belongs upstream rather than in statbus:

(1) src/0e_internal_functions.sql:15-45 - __internal_ddl_command_affects_managed_object() returns TRUE for ANY GRANT/REVOKE (and ALTER TABLE): 'For GRANT, REVOKE, and ALTER TABLE, we must always proceed, because objid is unreliable.' So a permission change on a completely unrelated object (observed: REVOKE ON FUNCTION public.upgrade_schedule) runs health_checks()'s full scan of every managed object and can raise from a statement that touched nothing managed. This is the defect that made a database restore abort.

(2) src/2h_health_checks.sql:340-373 - the REVOKE-propagation branch compares EXACT ACL entries: it scans each system_versioning table's aclexplode(relacl) for SELECT grantees and requires a matching aclexplode entry with EXECUTE on the as-of function. Other branches in the same file (lines 258 and 276) use has_function_privilege/has_table_privilege, which are inheritance-aware, and the propagation itself is inheritance-aware - so the check disagrees with the propagation it verifies. A role that inherits the privilege is judged to lack it, producing 'cannot revoke ... directly from "<view>", revoke ... from "<table>" instead' for a legitimate state.

CONSEQUENCE OBSERVED: any REVOKE anywhere raises on a database whose managed views lack an explicit entry for an inheriting role (7 of 9 for_portion_of_valid views, plus auth roles); during a pg_restore this aborted the entire restore, so a whole schema state produced an unrestorable dump.

FIX SHAPES (owner decides, he is the author): inheritance-aware comparison in branch (2) - my recommendation, it makes the check agree with the propagation; or exact propagation; plus optionally narrowing gate (1) so an unrelated GRANT/REVOKE does not run the scan, which is what would allow a restore to run with the check fully active. The extension repo has its own regression suite (sql/012_acl.sql, sql/093_event_trigger_health_checks.sql with expected/), so the fix can be proven there and then statbus re-runs its ACL test 352 after the pin bump, per AC#3.

NOTE: the statbus-side restore-time suppression (481 C) remains a separate and necessary accommodation - a dump replays a completed state and legitimately passes through transient states no live session produced - but it was never a substitute for fixing these two, and it should be re-tested for necessity after (1) is fixed.
<!-- SECTION:NOTES:END -->
