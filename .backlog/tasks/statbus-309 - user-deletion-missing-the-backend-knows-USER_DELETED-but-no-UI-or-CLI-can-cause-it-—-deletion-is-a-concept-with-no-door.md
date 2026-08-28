---
id: STATBUS-309
title: >-
  user-deletion-missing: the backend knows USER_DELETED but no UI or CLI can
  cause it — deletion is a concept with no door
status: To Do
assignee: []
created_date: '2026-08-28 22:33'
updated_date: '2026-08-28 22:34'
labels:
  - app
  - cli
  - auth
dependencies: []
priority: high
type: enhancement
ordinal: 302000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an admin removes a user through the product — one UI action, one database function — with the guards the schema ALREADY enforces. This is a door-installation, not a house-build.

THE DISCOVERY THAT RESHAPED THIS TICKET (2026-08-28, verified from the current schema): the King remembered deletion being implemented, and he was right — the DATABASE layer is complete. auth."user" carries deleted_at; public.login already refuses USER_DELETED; and the trigger set enforces every rule the King specified, today, verbatim: prevent_removal_of_last_admin (BEFORE DELETE OR UPDATE) blocks self-removal ('Admins cannot remove themselves — ask another admin') AND last-active-admin removal, fully soft-delete-aware; check_role_permission blocks managing roles the caller does not hold (pg_has_role MEMBER — the same-or-lower rule via role hierarchy); drop_user_role (AFTER DELETE) cleans up. Only the DOOR was never added: no exposed function sets deleted_at, and the admin UI has no action. The original author built the guard rails and stopped before the gate.

THE IMPLEMENTABLE SPEC, small by construction because the guards already fire on the write path:
1. MIGRATION: public.user_delete(p_user_id integer) — SECURITY DEFINER, admin-gated like public_user_create's pattern — sets deleted_at = now() via UPDATE auth."user" (an UPDATE, so prevent_removal_of_last_admin and check_role_permission fire exactly as built; the function ADDS NO GUARD LOGIC of its own — the triggers are the single source of the rules), then revokes the target's refresh sessions (the public.revoke_session machinery / direct session delete per its pattern). Optionally public.user_restore(p_user_id) clearing deleted_at, same trigger coverage. Follow the house SQL conventions (dollar-quote naming, doc/db regeneration, pg_regress test).
2. PG_REGRESS TEST: deleting a regular user succeeds and their login returns USER_DELETED; self-delete REFUSED by the trigger (assert the exact error); last-admin delete REFUSED; a regular_user caller cannot delete an admin (check_role_permission/RLS path); restore round-trip if built.
3. UI: the admin Users row gains Delete (confirm dialog naming the user), calling the function via the standard /rest RPC path; deleted users either drop from the default list or show a Deleted badge with Restore (implementer's call, note which). Trigger errors surface verbatim — they are already operator-quality messages.
4. CLI: optional follow-up, NOT this unit — a users prune verb is a semantics decision (.users.yml as authority for removals) that deserves its own small ruling.

STAFFING: engineer after STATBUS-274 (migration + SQL + a small frontend addition crosses lanes the mechanic's brief-completeness rule would strain). Architect verdict on the migration before landing, per house rule for auth-surface SQL.

THE CONCRETE FIRST CUSTOMER: Ghana's neutralized bootstrap placeholder (Regular role, rotated secret) — deleted through the front door as this feature's first live verification.

WHAT IS ACHIEVED: user removal is one guarded product action; the rules live in ONE place (the triggers, where they already are); and the surprising gap between built guards and missing door is closed.
<!-- SECTION:DESCRIPTION:END -->
