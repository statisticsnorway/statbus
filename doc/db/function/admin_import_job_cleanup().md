```sql
CREATE OR REPLACE FUNCTION admin.import_job_cleanup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Drop the snapshot table
    EXECUTE format('DROP TABLE IF EXISTS public.%I', OLD.import_information_snapshot_table_name);

    -- Drop the upload and data tables
    EXECUTE format('DROP TABLE IF EXISTS public.%I', OLD.upload_table_name);
    EXECUTE format('DROP TABLE IF EXISTS public.%I', OLD.data_table_name);


    RETURN OLD;
END;
$function$
```
