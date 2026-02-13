```sql
CREATE OR REPLACE FUNCTION admin.sector_custom_only_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    maybe_parent_id int := NULL;
    row RECORD;
BEGIN
    -- Find parent sector based on NEW.path
    IF public.nlevel(NEW.path) > 1 THEN
        SELECT id INTO maybe_parent_id
          FROM public.sector
         WHERE path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
           AND enabled
           AND custom;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent for path %', NEW.path;
        END IF;
        RAISE DEBUG 'maybe_parent_id %', maybe_parent_id;
    END IF;

    -- Perform an upsert operation on public.sector
    BEGIN
        INSERT INTO public.sector
            ( path
            , parent_id
            , name
            , description
            , updated_at
            , enabled
            , custom
            )
        VALUES
            ( NEW.path
            , maybe_parent_id
            , NEW.name
            , NEW.description
            , statement_timestamp()
            , TRUE -- Active
            , TRUE -- Custom
            )
        ON CONFLICT (path, enabled, custom)
        DO UPDATE SET
                parent_id = maybe_parent_id
              , name = NEW.name
              , description = NEW.description
              , updated_at = statement_timestamp()
              , enabled = TRUE
              , custom = TRUE
           RETURNING * INTO row;

        -- Log the upserted row
        RAISE DEBUG 'UPSERTED %', to_json(row);

    EXCEPTION WHEN unique_violation THEN
        DECLARE
            code varchar := regexp_replace(regexp_replace(NEW.path::TEXT, '[^0-9]', '', 'g'),'^([0-9]{2})(.+)$','\1.\2','');
            data JSONB := to_jsonb(NEW);
        BEGIN
           data := jsonb_set(data, '{code}', code::jsonb, true);
            RAISE EXCEPTION '% for row %', SQLERRM, data
                USING
                DETAIL = 'Failed during UPSERT operation',
                HINT = 'Check for path derived numeric code violations';
        END;
    END;

    RETURN NULL;
END;
$function$
```
