```sql
CREATE OR REPLACE FUNCTION public.import_job_accept_upload_columns(p_job_id integer, p_column_names text[])
 RETURNS text[]
 LANGUAGE sql
AS $function$
    SELECT admin.import_job_keep_ignored_columns(p_job_id, p_column_names);
$function$
```
