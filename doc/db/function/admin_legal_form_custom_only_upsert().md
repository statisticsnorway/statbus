```sql
CREATE OR REPLACE FUNCTION admin.legal_form_custom_only_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row RECORD;
BEGIN
    -- Perform an upsert operation on public.legal_form
    INSERT INTO public.legal_form
        ( code
        , name
        , updated_at
        , enabled
        , custom
        )
    VALUES
        ( NEW.code
        , NEW.name
        , statement_timestamp()
        , TRUE -- Active
        , TRUE -- Custom
        )
    ON CONFLICT (code, custom)
    DO UPDATE
        SET name = NEW.name
          , updated_at = statement_timestamp()
          , enabled = TRUE
       RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    -- Report the written row, so the statement's row count (INSERT 0 n,
    -- COPY n) is what was stored, never a silent 0.
    RETURN NEW;
END;
$function$
```
