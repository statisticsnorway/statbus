```sql
CREATE OR REPLACE FUNCTION admin.check_import_job_state_for_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    job_state public.import_job_state;
    job_slug text;
    job_id integer;
BEGIN
    -- Extract job_slug from trigger name (format: tablename_check_state_before_insert)
    -- Using job_slug instead of job_id ensures trigger names are stable across test runs
    -- since slugs are deterministic while job_ids may vary between test runs
    job_slug := TG_ARGV[0]::text;

    SELECT id, state INTO job_id, job_state
    FROM public.import_job
    WHERE slug = job_slug;

    IF job_state != 'waiting_for_upload' THEN
        RAISE EXCEPTION 'Cannot insert data: import job % (slug: %) is not in waiting_for_upload state', job_id, job_slug;
    END IF;

    RETURN NULL; -- For BEFORE triggers with FOR EACH STATEMENT
END;
$function$
```
