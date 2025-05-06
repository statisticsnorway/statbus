```sql
CREATE OR REPLACE FUNCTION admin.import_job_state_change_before()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_timestamp TIMESTAMPTZ := now();
    v_row_count INTEGER;
BEGIN
    -- Record timestamps for state changes if not already recorded
    IF NEW.state = 'preparing_data' AND NEW.preparing_data_at IS NULL THEN
        NEW.preparing_data_at := v_timestamp;
    END IF;

    IF NEW.state = 'analysing_data' AND NEW.analysis_start_at IS NULL THEN
        NEW.analysis_start_at := v_timestamp;
    END IF;

    -- Set stop timestamps when transitioning *out* of a processing state
    IF OLD.state = 'analysing_data' AND NEW.state != OLD.state AND NEW.analysis_stop_at IS NULL THEN
        NEW.analysis_stop_at := v_timestamp;
    END IF;

    IF OLD.state = 'processing_data' AND NEW.state != OLD.state AND NEW.processing_stop_at IS NULL THEN
        NEW.processing_stop_at := v_timestamp;
    END IF;

    -- Record timestamps for approval/rejection states
    IF NEW.state = 'approved' AND NEW.changes_approved_at IS NULL THEN
        NEW.changes_approved_at := v_timestamp;
    END IF;

    IF NEW.state = 'rejected' AND NEW.changes_rejected_at IS NULL THEN
        NEW.changes_rejected_at := v_timestamp;
    END IF;

    -- Record start timestamp for processing_data state
    IF NEW.state = 'processing_data' AND NEW.processing_start_at IS NULL THEN
        NEW.processing_start_at := v_timestamp;
    END IF;

    -- Derive total_rows when state changes from waiting_for_upload to upload_completed
    IF OLD.state = 'waiting_for_upload' AND NEW.state = 'upload_completed' THEN
        -- Count rows in the upload table
        EXECUTE format('SELECT COUNT(*) FROM public.%I', NEW.upload_table_name) INTO v_row_count;
        NEW.total_rows := v_row_count;

        -- Set priority using the dedicated sequence
        -- Lower values = higher priority, so earlier jobs get lower sequence values
        -- This ensures jobs are processed in the order they were created
        NEW.priority := nextval('public.import_job_priority_seq')::integer;

        RAISE DEBUG 'Set total_rows to % for import job %', v_row_count, NEW.id;
    END IF;

    RETURN NEW;
END;
$function$
```
