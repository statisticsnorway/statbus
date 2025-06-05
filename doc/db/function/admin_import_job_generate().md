```sql
CREATE OR REPLACE FUNCTION admin.import_job_generate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM admin.import_job_generate(NEW);
    RETURN NEW;
END;
$function$
```
