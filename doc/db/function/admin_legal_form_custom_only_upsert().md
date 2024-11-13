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
        , active
        , custom
        )
    VALUES
        ( NEW.code
        , NEW.name
        , statement_timestamp()
        , TRUE -- Active
        , TRUE -- Custom
        )
    ON CONFLICT (code, active, custom)
    DO UPDATE
        SET name = NEW.name
          , updated_at = statement_timestamp()
          , active = TRUE
          , custom = TRUE
       WHERE legal_form.id = EXCLUDED.id
       RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
```
