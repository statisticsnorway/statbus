```sql
CREATE OR REPLACE FUNCTION admin.upsert_legal_form_system()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    -- The system row is updated on (code, custom), never the custom override.
    -- A reload corrects the label only: an existing system row keeps its
    -- enabled flag (the operator's custom-only upload disables system rows on
    -- purpose), and a new system code starts disabled while an enabled custom
    -- override of the code exists.
    INSERT INTO public.legal_form (code, name, enabled, custom, updated_at)
    VALUES
        ( NEW.code
        , NEW.name
        , NOT EXISTS (
            SELECT 1 FROM public.legal_form AS override
             WHERE override.code = NEW.code
               AND override.custom
               AND override.enabled)
        , 'f'
        , statement_timestamp()
        )
    ON CONFLICT (code, custom) DO UPDATE SET
        name = NEW.name,
        updated_at = statement_timestamp()
    RETURNING * INTO row;

    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
```
