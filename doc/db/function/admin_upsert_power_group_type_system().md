```sql
CREATE OR REPLACE FUNCTION admin.upsert_power_group_type_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
    _constraint text;
    _detail text;
BEGIN
    IF EXISTS (SELECT 1 FROM public.power_group_type AS t WHERE t.code = NEW.code AND t.custom IS DISTINCT FROM 'f') THEN
        RAISE EXCEPTION 'power_group_type code "%" already exists as a custom entry, so this system (standard) upload cannot add or change it', NEW.code
            USING ERRCODE = 'unique_violation', HINT = 'The standard list cannot overwrite an entry an operator uploaded. Remove or rename the custom entry first.';
    END IF;

    BEGIN
        INSERT INTO public.power_group_type (code, name, enabled, custom, updated_at)
        VALUES (NEW.code, NEW.name, TRUE, 'f', statement_timestamp())
        ON CONFLICT (code) DO UPDATE SET
            name = NEW.name,
            updated_at = statement_timestamp()
        RETURNING * INTO row;
    EXCEPTION WHEN unique_violation THEN
        -- Any other unique key (e.g. name) collides: say which, for this row.
        GET STACKED DIAGNOSTICS _constraint = CONSTRAINT_NAME, _detail = PG_EXCEPTION_DETAIL;
        RAISE EXCEPTION 'power_group_type code "%" cannot be stored: another entry already has a value that must be unique (%)', NEW.code, _detail
            USING ERRCODE = 'unique_violation', CONSTRAINT = _constraint, HINT = 'Each value in a unique column (such as name) may be used by only one entry. Change the uploaded value, or change the existing entry first.';
    END;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
```
