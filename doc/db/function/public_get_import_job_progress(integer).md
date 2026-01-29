```sql
CREATE OR REPLACE FUNCTION public.get_import_job_progress(job_id integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    job public.import_job;
    row_states json;
BEGIN
    -- Get the job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RETURN json_build_object('error', format('Import job %s not found', job_id));
    END IF;

    -- Get row state counts including analysis states
    EXECUTE format(
        'SELECT json_build_object(
            ''pending'', COUNT(*) FILTER (WHERE state = ''pending''),
            ''analysing'', COUNT(*) FILTER (WHERE state = ''analysing''),
            ''analysed'', COUNT(*) FILTER (WHERE state = ''analysed''),
            ''processing'', COUNT(*) FILTER (WHERE state = ''processing''),
            ''processed'', COUNT(*) FILTER (WHERE state = ''processed''),
            ''error'', COUNT(*) FILTER (WHERE state = ''error'')
        ) FROM public.%I',
        job.data_table_name
    ) INTO row_states;

    -- Return detailed progress information
    RETURN json_build_object(
        'job_id', job.id,
        'state', job.state,
        'total_rows', job.total_rows,
        'analysis_completed_pct', job.analysis_completed_pct,
        'analysis_rows_per_sec', job.analysis_rows_per_sec,
        'imported_rows', job.imported_rows,
        'import_completed_pct', job.import_completed_pct,
        'import_rows_per_sec', job.import_rows_per_sec,
        'last_progress_update', job.last_progress_update,
        'row_states', row_states
    );
END;
$function$
```
