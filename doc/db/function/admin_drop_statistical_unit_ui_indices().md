```sql
CREATE OR REPLACE FUNCTION admin.drop_statistical_unit_ui_indices()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    r RECORD;
BEGIN
    -- Drop all non-PK indices using pattern matching
    FOR r IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'statistical_unit'
          AND indexname != 'statistical_unit_temporal_pk'  -- Keep the PK
        ORDER BY indexname
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS public.%I', r.indexname);
        RAISE DEBUG 'Dropped index %', r.indexname;
    END LOOP;

    RAISE DEBUG 'Dropped all statistical_unit UI indices';
END;
$function$
```
