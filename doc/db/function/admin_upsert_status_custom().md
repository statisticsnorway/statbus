```sql
CREATE OR REPLACE FUNCTION admin.upsert_status_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
    _constraint text;
    _detail text;
BEGIN
    BEGIN
        INSERT INTO public.status (code, name, priority, assigned_by_default, used_for_counting, enabled, custom, updated_at)
        VALUES (NEW.code, NEW.name, NEW.priority, NEW.assigned_by_default, NEW.used_for_counting, TRUE, 't', statement_timestamp())
        ON CONFLICT (code, custom) DO UPDATE SET
            name = NEW.name, priority = NEW.priority, assigned_by_default = NEW.assigned_by_default, used_for_counting = NEW.used_for_counting, enabled = TRUE,
            updated_at = statement_timestamp()
        RETURNING * INTO row;
    EXCEPTION WHEN unique_violation THEN
        -- Any other unique key (e.g. name) collides: say which, for this row.
        GET STACKED DIAGNOSTICS _constraint = CONSTRAINT_NAME, _detail = PG_EXCEPTION_DETAIL;
        RAISE EXCEPTION 'status code "%" cannot be stored: another entry already has a value that must be unique (%)', NEW.code, _detail
            USING ERRCODE = 'unique_violation', CONSTRAINT = _constraint, HINT = 'Each value in a unique column (such as name) may be used by only one entry. Change the uploaded value, or change the existing entry first.';
    END;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
```
