```sql
CREATE OR REPLACE FUNCTION admin.upsert_country()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO public.country (iso_2, iso_3, iso_num, name, active, custom, updated_at)
    VALUES (NEW.iso_2, NEW.iso_3, NEW.iso_num, NEW.name, true, false, statement_timestamp())
    ON CONFLICT (iso_2, iso_3, iso_num, name)
    DO UPDATE SET
        name = EXCLUDED.name,
        custom = false,
        updated_at = statement_timestamp()
    WHERE country.id = EXCLUDED.id;
    RETURN NULL;
END;
$function$
```
