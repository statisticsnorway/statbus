```sql
CREATE OR REPLACE FUNCTION admin.update_import_job_state_after_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    row_count INTEGER;
    job_slug text;
BEGIN
    -- Extract job_slug from trigger arguments
    -- Using job_slug instead of job_id ensures trigger names are stable across test runs
    -- since slugs are deterministic while job_ids may vary between test runs
    job_slug := TG_ARGV[0]::text;

    -- Count rows in the table
    EXECUTE format('SELECT COUNT(*) FROM %s', TG_TABLE_NAME) INTO row_count;

    -- Only update state if rows were actually inserted
    IF row_count > 0 THEN
        UPDATE public.import_job
        SET state = 'upload_completed'
        WHERE slug = job_slug
        AND state = 'waiting_for_upload';
    END IF;

    RETURN NULL; -- For AFTER triggers with FOR EACH STATEMENT
END;
$function$
```
