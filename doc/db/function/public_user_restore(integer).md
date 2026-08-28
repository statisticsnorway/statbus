```sql
CREATE OR REPLACE FUNCTION public.user_restore(p_user_id integer)
 RETURNS TABLE(id integer, email text, deleted_at timestamp with time zone)
 LANGUAGE plpgsql
AS $function$
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
$function$
```
