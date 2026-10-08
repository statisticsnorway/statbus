```sql
CREATE OR REPLACE FUNCTION admin.upsert_activity_category()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    standardCode text;
    standardId int;
BEGIN
    -- Access the standard code passed as an argument
    standardCode := TG_ARGV[0];
    SELECT id INTO standardId FROM public.activity_category_standard WHERE code = standardCode;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Unknown activity_category_standard.code %', standardCode;
    END IF;

    -- Record that this statement addresses the code, so the statement-level
    -- admin.delete_stale_activity_category removes exactly the complement.
    -- (Triggers on views cannot have transition tables.)
    IF to_regclass('pg_temp.activity_category_addressed') IS NULL THEN
        CREATE TEMP TABLE activity_category_addressed
            ( standard_id int NOT NULL
            , path public.ltree NOT NULL
            , PRIMARY KEY (standard_id, path)
            ) ON COMMIT DROP;
    END IF;
    INSERT INTO pg_temp.activity_category_addressed(standard_id, path)
    VALUES (standardId, NEW.path)
    ON CONFLICT DO NOTHING;

    WITH parent AS (
        SELECT activity_category.id
          FROM public.activity_category
         WHERE standard_id = standardId
           AND path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
           AND enabled
    )
    INSERT INTO public.activity_category
        ( standard_id
        , path
        , parent_id
        , name
        , description
        , updated_at
        , enabled
        , custom
        )
    SELECT standardId
         , NEW.path
         , (SELECT id FROM parent)
         , NEW.name
         , NEW.description
         , statement_timestamp()
         -- A new system code is shadowed by an existing custom override.
         , NOT EXISTS (
             SELECT 1 FROM public.activity_category AS override
              WHERE override.standard_id = standardId
                AND override.path OPERATOR(public.=) NEW.path
                AND override.custom
                AND override.enabled)
         , false
    ON CONFLICT (standard_id, path, custom)
    DO UPDATE SET parent_id = (SELECT id FROM parent)
                , name = NEW.name
                , description = NEW.description
                , updated_at = statement_timestamp()
                ;
    RETURN NEW;
END;
$function$
```
