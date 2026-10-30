---
id: STATBUS-309
title: >-
  user-deletion-missing: the backend knows USER_DELETED but no UI or CLI can
  cause it — deletion is a concept with no door
status: Done
assignee: []
created_date: '2026-08-28 22:33'
updated_date: '2026-08-28 23:17'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Architect verdict (2026-08-29): APPROVED conditionally.** Reviewed on frozen bytes; approval highlights the prosecdef=f baseline assertion (the one edit that would reopen the RLS-bypass hole now fails a test), correct NULL-caller handling in prevent_self_soft_delete, clean down migration whose refusal to clear deleted_at is deliberate (clearing would silently reactivate deliberately-removed accounts). Conditions before landing: (1) 098 must RUN green — nothing has been observed yet; (2) scenario G is non-optional: the zero-row RETURNING…INTO semantics were reasoned, not observed — G is the observation; (3) scenario D can refuse two ways (RLS zero-row no-op vs permission denied on base UPDATE) — the actually-printed shape must be read before blessing the expected file. Optional non-blocking: WHEN (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL) on the trigger to skip unrelated updates. Engineer holds verification, queued behind the straggler drain.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LANDED at f19b25910. The door is installed: public.user_delete/user_restore as SECURITY INVOKER with zero guard logic (triggers + RLS remain the single source — the DEFINER shape was refuted by catalog check: owner bypasses RLS, so DEFINER would have opened delete-any-regular-user to anyone with EXECUTE while admin-path tests stayed green; 098 pins prosecdef=f structurally). One genuinely-missing rule added: auth.prevent_self_soft_delete, the universal self-delete refusal, sibling of prevent_removal_of_last_admin. 098 red-then-green with all 249 lines read before blessing; architect approved with all three conditions observed (G's zero-row RETURNING-INTO, D's RLS zero-row refusal shape, 098 run green). Down migration deliberately preserves deleted_at. UI: Delete/Restore row actions on admin Users via /rest RPC, trigger errors verbatim. Recorded follow-ups: (1) the WHEN clause on the trigger rides the next seed rebuild — KEEP the early-return in the body when it goes in (architect: the clause is optimisation, the body is the correctness guard; also preserves 098's line-19 CONTEXT pin); (2) first live customer: Ghana's neutralized bootstrap placeholder gets deleted through this door once rc.17 lands there; (3) STATBUS-313 (the runner's vacuous-green gap) was discovered during this unit's verification.
<!-- SECTION:FINAL_SUMMARY:END -->
