```sql
CREATE OR REPLACE FUNCTION admin.import_job_progress_notify()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Notify clients about progress update
    PERFORM pg_notify(
        'import_job_progress',
        json_build_object(
            'job_id', NEW.id,
            'total_rows', NEW.total_rows,
            'imported_rows', NEW.imported_rows,
            'import_completed_pct', NEW.import_completed_pct,
            'import_rows_per_sec', NEW.import_rows_per_sec,
            'state', NEW.state
        )::text
    );
    RETURN NEW;
END;
$function$
```
