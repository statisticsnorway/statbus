```sql
CREATE OR REPLACE FUNCTION admin.import_job_progress_update()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Update last_progress_update timestamp when imported_rows changes
    IF OLD.imported_rows IS DISTINCT FROM NEW.imported_rows THEN
        NEW.last_progress_update := clock_timestamp();
    END IF;

    -- Calculate import_completed_pct
    IF NEW.total_rows IS NULL OR NEW.total_rows = 0 THEN
        NEW.import_completed_pct := 0;
    ELSE
        NEW.import_completed_pct := ROUND((NEW.imported_rows::numeric / NEW.total_rows::numeric) * 100, 2);
    END IF;

    -- Calculate import_rows_per_sec
    IF NEW.imported_rows = 0 OR NEW.import_start_at IS NULL THEN
        NEW.import_rows_per_sec := 0;
    ELSIF NEW.state = 'finished' AND NEW.import_stop_at IS NOT NULL THEN
        NEW.import_rows_per_sec := CASE
            WHEN EXTRACT(EPOCH FROM (NEW.import_stop_at - NEW.import_start_at)) <= 0 THEN 0
            ELSE ROUND((NEW.imported_rows::numeric / EXTRACT(EPOCH FROM (NEW.import_stop_at - NEW.import_start_at))), 2)
        END;
    ELSE
        NEW.import_rows_per_sec := CASE
            WHEN EXTRACT(EPOCH FROM (COALESCE(NEW.last_progress_update, clock_timestamp()) - NEW.import_start_at)) <= 0 THEN 0
            ELSE ROUND((NEW.imported_rows::numeric / EXTRACT(EPOCH FROM (COALESCE(NEW.last_progress_update, clock_timestamp()) - NEW.import_start_at))), 2)
        END;
    END IF;

    RETURN NEW;
END;
$function$
```
