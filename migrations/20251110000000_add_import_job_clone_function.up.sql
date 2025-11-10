BEGIN;

CREATE FUNCTION public.import_job_clone(p_source_job_id integer, p_slug text DEFAULT NULL)
RETURNS public.import_job
LANGUAGE plpgsql AS $function$
DECLARE
    v_source_job public.import_job;
    v_new_job public.import_job;
    v_source_upload_table_exists BOOLEAN;
BEGIN
    -- 1. Get the source job record
    SELECT * INTO v_source_job FROM public.import_job WHERE id = p_source_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source import job with ID % not found.', p_source_job_id;
    END IF;

    -- 2. Create a new job by inserting a copy of the old one's configuration.
    -- The BEFORE INSERT trigger `import_job_derive_trigger` will handle setting a new slug,
    -- table names, snapshot, user_id (to current user), expires_at, etc.
    INSERT INTO public.import_job (
        slug,
        description,
        note,
        time_context_ident,
        default_valid_from,
        default_valid_to,
        default_data_source_code,
        analysis_batch_size,
        processing_batch_size,
        review,
        edit_comment,
        definition_id
    ) VALUES (
        p_slug,
        'Clone of job #' || v_source_job.id || ': ' || COALESCE(v_source_job.description, ''),
        v_source_job.note,
        v_source_job.time_context_ident,
        CASE WHEN v_source_job.time_context_ident IS NOT NULL THEN NULL ELSE v_source_job.default_valid_from END,
        CASE WHEN v_source_job.time_context_ident IS NOT NULL THEN NULL ELSE v_source_job.default_valid_to END,
        v_source_job.default_data_source_code,
        v_source_job.analysis_batch_size,
        v_source_job.processing_batch_size,
        v_source_job.review,
        v_source_job.edit_comment,
        v_source_job.definition_id
    ) RETURNING * INTO v_new_job;

    -- 3. Check if the source upload table exists.
    SELECT to_regclass('public.' || v_source_job.upload_table_name) IS NOT NULL INTO v_source_upload_table_exists;

    -- 4. If it exists, copy data from old upload table to new upload table.
    IF v_source_upload_table_exists THEN
        RAISE DEBUG '[Job Clone] Copying data from % to %', v_source_job.upload_table_name, v_new_job.upload_table_name;
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I', v_new_job.upload_table_name, v_source_job.upload_table_name);
        
        -- The AFTER INSERT trigger on the new upload table will automatically set the
        -- new job's state to 'upload_completed', which in turn will enqueue it for processing.
        RAISE DEBUG '[Job Clone] Data copy complete. Job % has been enqueued automatically.', v_new_job.id;
    ELSE
        RAISE DEBUG '[Job Clone] Source upload table % not found. New job % created in "waiting_for_upload" state.', v_source_job.upload_table_name, v_new_job.id;
    END IF;
    
    -- 5. Return the newly created job.
    RETURN v_new_job;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.import_job_clone(integer, text) TO authenticated;

END;
