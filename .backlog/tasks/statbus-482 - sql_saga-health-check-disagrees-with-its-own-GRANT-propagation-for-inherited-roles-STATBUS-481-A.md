---
id: STATBUS-482
title: >-
  sql_saga health check disagrees with its own GRANT propagation for inherited
  roles (STATBUS-481 A)
status: To Do
assignee: []
created_date: '2026-10-08 19:24'
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
