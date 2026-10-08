```sql
CREATE OR REPLACE FUNCTION admin.delete_stale_country()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- A load through country_view is the complete country list: the countries
    -- the statement did NOT address are stale. admin.upsert_country recorded
    -- every addressed code; a statement that addressed none deletes nothing.
    -- A stale country still referenced (settings, location, person) fails
    -- honestly on its RESTRICT foreign key rather than being kept silently.
    IF to_regclass('pg_temp.country_addressed') IS NULL THEN
        RETURN NULL;
    END IF;

    DELETE FROM public.country AS c
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_temp.country_addressed AS addressed
         WHERE addressed.iso_2 = c.iso_2);

    DROP TABLE pg_temp.country_addressed;
    RETURN NULL;
END;
$function$
```
