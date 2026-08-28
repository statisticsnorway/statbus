```sql
CREATE OR REPLACE FUNCTION auth.prevent_self_soft_delete()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$
```
