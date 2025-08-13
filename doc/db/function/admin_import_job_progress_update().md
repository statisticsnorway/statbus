```sql
CREATE OR REPLACE FUNCTION admin.import_job_progress_update()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Update last_progress_update timestamp when progress changes
    IF OLD.imported_rows IS DISTINCT FROM NEW.imported_rows OR OLD.completed_analysis_steps_weighted IS DISTINCT FROM NEW.completed_analysis_steps_weighted THEN
        NEW.last_progress_update := clock_timestamp();
    END IF;

    -- Calculate analysis_completed_pct using weighted steps for more granular progress
    IF NEW.total_analysis_steps_weighted IS NULL OR NEW.total_analysis_steps_weighted = 0 THEN
        NEW.analysis_completed_pct := 0;
    ELSE
        NEW.analysis_completed_pct := ROUND((NEW.completed_analysis_steps_weighted::numeric / NEW.total_analysis_steps_weighted::numeric) * 100, 2);
    END IF;

    -- Calculate analysis_rows_per_sec. This is only meaningful once the phase is complete.
    IF NEW.analysis_stop_at IS NOT NULL AND NEW.analysis_start_at IS NOT NULL AND NEW.total_rows > 0 THEN
        NEW.analysis_rows_per_sec := CASE
            WHEN EXTRACT(EPOCH FROM (NEW.analysis_stop_at - NEW.analysis_start_at)) <= 0 THEN 0
            ELSE ROUND((NEW.total_rows::numeric / EXTRACT(EPOCH FROM (NEW.analysis_stop_at - NEW.analysis_start_at))), 2)
        END;
    ELSE
        NEW.analysis_rows_per_sec := 0;
    END IF;

    -- Calculate import_completed_pct
    IF NEW.total_rows IS NULL OR NEW.total_rows = 0 THEN
        NEW.import_completed_pct := 0;
    ELSE
        NEW.import_completed_pct := ROUND((NEW.imported_rows::numeric / NEW.total_rows::numeric) * 100, 2);
    END IF;

    -- Calculate import_rows_per_sec (still based on fully processed rows)
    IF NEW.imported_rows = 0 OR NEW.processing_start_at IS NULL THEN
        NEW.import_rows_per_sec := 0;
    ELSIF NEW.state = 'finished' AND NEW.processing_stop_at IS NOT NULL THEN
        NEW.import_rows_per_sec := CASE
            WHEN EXTRACT(EPOCH FROM (NEW.processing_stop_at - NEW.processing_start_at)) <= 0 THEN 0
            ELSE ROUND((NEW.imported_rows::numeric / EXTRACT(EPOCH FROM (NEW.processing_stop_at - NEW.processing_start_at))), 2)
        END;
    ELSE
        NEW.import_rows_per_sec := CASE
            WHEN EXTRACT(EPOCH FROM (COALESCE(NEW.last_progress_update, clock_timestamp()) - NEW.processing_start_at)) <= 0 THEN 0
            ELSE ROUND((NEW.imported_rows::numeric / EXTRACT(EPOCH FROM (COALESCE(NEW.last_progress_update, clock_timestamp()) - NEW.processing_start_at))), 2)
        END;
    END IF;

    RETURN NEW;
END;
$function$
```
