BEGIN;

-- STATBUS-309: the door for a concept that already had its guard rails.
--
-- auth."user" has carried deleted_at all along, public.login already refuses a
-- deleted user with USER_DELETED, and the trigger set already enforces the
-- admin rules. What was missing was any way to CAUSE it: no exposed function
-- set deleted_at, and the admin UI had no action. This adds the door and one
-- missing rule, and deliberately adds no others.

-- ── THE ONE MISSING RULE: NOBODY SOFT-DELETES THEMSELVES ────────────────────
--
-- auth.prevent_removal_of_last_admin already refuses an ADMIN removing
-- themselves. That refusal is scoped to admins because it lives inside the
-- last-admin rule, which only engages when the target was an active admin. A
-- regular user soft-deleting their own row met no rule at all.
--
-- WHY A SIBLING TRIGGER RATHER THAN AN ARM OF THE EXISTING ONE (architect
-- ruling): one rule, one name. Folding "nobody deletes themselves" into a
-- function called prevent_removal_of_last_admin would hide a universal rule
-- inside a special-case name, where the next reader looking for it would not
-- think to look.
--
-- WHY A TRIGGER RATHER THAN A CHECK INSIDE user_delete(): the architecture
-- recommends direct PostgREST access, so the function is not the only writer
-- and must not be the only place the rule lives. A trigger covers every writer
-- there will ever be — the function below, a direct PATCH from the app, a
-- psql session, a future CLI verb.
CREATE OR REPLACE FUNCTION auth.prevent_self_soft_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $prevent_self_soft_delete$
DECLARE
    _caller_id integer;
BEGIN
    -- Only a transition INTO the soft-deleted state is a removal. Editing an
    -- already-deleted row, or any update that leaves deleted_at NULL, is not.
    IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NULL THEN
        RETURN NEW;
    END IF;

    _caller_id := auth.uid();

    -- A NULL caller means there is no authenticated identity to compare
    -- against — a superuser/psql session, or migration-time maintenance. Same
    -- treatment the sibling trigger already gives that case: this rule is
    -- about a person removing themselves, and with no person there is nobody
    -- to protect from the mistake.
    IF _caller_id IS NOT NULL AND _caller_id = OLD.id THEN
        RAISE EXCEPTION 'Users cannot delete themselves (%)', OLD.email
            USING HINT = 'Ask another admin to delete this account.';
    END IF;

    RETURN NEW;
END;
$prevent_self_soft_delete$;

COMMENT ON FUNCTION auth.prevent_self_soft_delete() IS
    'Refuses a soft-delete whose caller is the target (STATBUS-309). Universal — '
    'auth.prevent_removal_of_last_admin covers the same ground for admins only, '
    'because that refusal is scoped to the last-admin rule it lives inside.';

-- Fires on UPDATE only: a hard DELETE is already covered by
-- prevent_removal_of_last_admin's own DELETE branch for admins, and hard
-- deletion is not what this product does to users.
CREATE TRIGGER prevent_self_soft_delete_trigger
    BEFORE UPDATE ON auth."user"
    FOR EACH ROW EXECUTE FUNCTION auth.prevent_self_soft_delete();

-- ── THE DOOR ────────────────────────────────────────────────────────────────
--
-- SECURITY INVOKER, and that is the load-bearing decision, not a default.
--
-- Verified against this schema rather than assumed: public.user_create is
-- prosecdef = f and gates on the admin_all_access RLS policy. RLS on
-- auth."user" is enabled but NOT forced, so a SECURITY DEFINER function would
-- run as the owner and bypass that policy entirely. And the triggers do not
-- close the gap: check_role_permission only fires when statbus_role CHANGES,
-- which a soft-delete does not do, and prevent_removal_of_last_admin only
-- engages when the target was an active admin. For a regular-user target a
-- DEFINER function would therefore be guarded by nothing at all, while still
-- refusing the admin cases — passing every obvious test over a wide-open path.
--
-- As INVOKER the rules are exactly where the ticket wants them: RLS decides
-- WHO may touch a row, and the triggers decide WHICH transitions are legal.
-- This function adds no rule of its own.
CREATE OR REPLACE FUNCTION public.user_delete(p_user_id integer)
RETURNS TABLE(id integer, email text, deleted_at timestamptz)
LANGUAGE plpgsql
AS $user_delete$
DECLARE
    _user_delete record;
BEGIN
    UPDATE auth."user" AS u
       SET deleted_at = now()
     WHERE u.id = p_user_id
       AND u.deleted_at IS NULL
    RETURNING u.id, u.email, u.deleted_at INTO _user_delete;

    -- No row means either no such user, or one RLS would not show this caller,
    -- or one already deleted. Idempotent-but-honest: say nothing happened
    -- rather than claim a deletion that did not occur.
    IF _user_delete.id IS NULL THEN
        RETURN;
    END IF;

    -- Revoke the target's refresh sessions so the deletion takes effect on
    -- their NEXT request rather than whenever their current token expires.
    --
    -- NOT public.revoke_session: that function resolves its target from the
    -- CALLER's own JWT sub and can only revoke the caller's own session — it
    -- is the "log myself out" primitive, not an admin one. A direct delete is
    -- what the admin_all_refresh_sessions policy exists for.
    DELETE FROM auth.refresh_session WHERE user_id = p_user_id;

    RETURN QUERY SELECT _user_delete.id, _user_delete.email::text, _user_delete.deleted_at;
END;
$user_delete$;

COMMENT ON FUNCTION public.user_delete(integer) IS
    'Soft-deletes a user (deleted_at) and revokes their refresh sessions (STATBUS-309). '
    'SECURITY INVOKER on purpose: the admin_all_access RLS policy is the admin gate, and '
    'a DEFINER function would bypass it. Adds no guard logic — the triggers own the rules.';

-- ── THE WAY BACK ────────────────────────────────────────────────────────────
--
-- Restore is the same shape in reverse and takes the same trigger coverage:
-- clearing deleted_at is an UPDATE, so check_role_permission and
-- prevent_removal_of_last_admin see it, and RLS gates the caller identically.
-- It exists because a soft-delete that cannot be undone is a hard delete with
-- extra steps.
CREATE OR REPLACE FUNCTION public.user_restore(p_user_id integer)
RETURNS TABLE(id integer, email text, deleted_at timestamptz)
LANGUAGE plpgsql
AS $user_restore$
DECLARE
    _user_restore record;
BEGIN
    UPDATE auth."user" AS u
       SET deleted_at = NULL
     WHERE u.id = p_user_id
       AND u.deleted_at IS NOT NULL
    RETURNING u.id, u.email, u.deleted_at INTO _user_restore;

    IF _user_restore.id IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY SELECT _user_restore.id, _user_restore.email::text, _user_restore.deleted_at;
END;
$user_restore$;

COMMENT ON FUNCTION public.user_restore(integer) IS
    'Clears deleted_at, restoring a soft-deleted user (STATBUS-309). SECURITY INVOKER, '
    'same reasoning as user_delete.';

GRANT EXECUTE ON FUNCTION public.user_delete(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_restore(integer) TO authenticated;

END;
