```sql
CREATE OR REPLACE FUNCTION admin.import_job_cleanup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    RAISE DEBUG '[Job %] Cleaning up tables: %, %', OLD.id, OLD.upload_table_name, OLD.data_table_name;
    -- Snapshot table is removed automatically when the job row is deleted or updated

    -- Drop the upload and data tables
    EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', OLD.upload_table_name);
    EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', OLD.data_table_name);

    -- Ensure the new tables are removed from PostgREST
    NOTIFY pgrst, 'reload schema';
    RAISE DEBUG '[Job %] Cleanup complete, notified PostgREST', OLD.id;

    RETURN OLD;
END;
$function$
```
