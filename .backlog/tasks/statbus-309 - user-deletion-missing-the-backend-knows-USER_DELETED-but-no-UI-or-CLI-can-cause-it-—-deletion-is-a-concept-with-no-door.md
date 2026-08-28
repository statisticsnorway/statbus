---
id: STATBUS-309
title: >-
  user-deletion-missing: the backend knows USER_DELETED but no UI or CLI can
  cause it — deletion is a concept with no door
status: To Do
assignee: []
created_date: '2026-08-28 22:33'
labels:
  - app
  - cli
  - auth
dependencies: []
priority: medium
type: enhancement
ordinal: 302000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an admin must be able to remove a user through the product — UI or CLI — without anyone touching the database by hand. The backend already knows how; nothing lets you ask it.

THE GAP, found live by the King on Ghana's first day (2026-08-28): the admin Users page (app/admin/users) lists users with an edit pencil and Create — no delete, no deactivate. The CLI has only `users create` (upsert semantics — which is also WHY a stale user lingers: nothing prunes). Yet the data model is ready: auth_user.deleted_at exists, and public.login already returns USER_DELETED for a soft-deleted user — the refusal semantics are built and waiting.

THE CONCRETE INSTANCE: Ghana's bootstrap placeholder admin (created during install, password since rotated to a random secret, role Regular) lingers in the user table after the real users replaced it in .users.yml — users create upserts, never prunes. It is neutralized (unguessable secret, non-admin) but it should not exist, and today no product path can remove it.

THE SHAPE (architect rules the details; likely next round — app + db function + CLI): (1) a public.user_delete (or deactivate) SECURITY DEFINER function setting deleted_at, revoking sessions (public.revoke_session machinery exists), guarded so an admin cannot delete the last admin or themselves without confirmation semantics; (2) the admin UI gains delete/deactivate on the user row with a confirm step, honoring the existing USER_DELETED login refusal; (3) optionally `./sb users` gains a prune-or-delete verb so .users.yml can be authoritative for removals too — with the same last-admin guard. Soft delete (deleted_at) not hard DELETE, matching what login already expects; whether hard-purge ever exists is a separate retention question.

WHAT IS ACHIEVED: user removal is a product feature instead of a database intervention, and the next bootstrap placeholder dies through the front door.
<!-- SECTION:DESCRIPTION:END -->
