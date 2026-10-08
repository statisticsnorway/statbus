```sql
CREATE OR REPLACE FUNCTION admin.upsert_country()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Record that this statement addresses the code, so the statement-level
    -- admin.delete_stale_country removes exactly the complement.
    -- (Triggers on views cannot have transition tables.)
    IF to_regclass('pg_temp.country_addressed') IS NULL THEN
        CREATE TEMP TABLE country_addressed
            ( iso_2 text PRIMARY KEY
            ) ON COMMIT DROP;
    END IF;
    INSERT INTO pg_temp.country_addressed(iso_2)
    VALUES (NEW.iso_2)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.country (iso_2, iso_3, iso_num, name, enabled, custom, updated_at)
    VALUES (NEW.iso_2, NEW.iso_3, NEW.iso_num, NEW.name, true, false, statement_timestamp())
    ON CONFLICT (iso_2)
    DO UPDATE SET
        iso_3 = EXCLUDED.iso_3,
        iso_num = EXCLUDED.iso_num,
        name = EXCLUDED.name,
        custom = false,
        updated_at = statement_timestamp();
    -- Report the written row, so the statement's row count is what was stored.
    RETURN NEW;
END;
$function$
```
