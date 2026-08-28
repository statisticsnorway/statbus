```sql
CREATE OR REPLACE FUNCTION public.user_delete(p_user_id integer)
 RETURNS TABLE(id integer, email text, deleted_at timestamp with time zone)
 LANGUAGE plpgsql
AS $function$
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
$function$
```
