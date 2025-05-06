```sql
CREATE OR REPLACE PROCEDURE admin.analyse_legal_unit(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_row RECORD;
    v_update_sql TEXT;
    v_select_sql TEXT;
    v_data_source_id INT;
    v_legal_form_id INT;
    v_status_id INT;
    v_sector_id INT;
    v_unit_size_id INT;
    v_computed_valid_from DATE;
    v_computed_valid_to DATE;
    v_error_count INT := 0;
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_unit: Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot; -- Assign snapshot from the job record

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    -- Find the target details for legal_unit
    SELECT * INTO v_step FROM public.import_step WHERE code = 'legal_unit';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] legal_unit target not found', p_job_id;
    END IF;

    -- Prepare parts of the dynamic SQL
    -- Note: This assumes specific column names defined in the default definitions migration.
    -- A more robust implementation might fetch column names from the snapshot.
    v_select_sql := format($$
        SELECT
            ctid,
            NULLIF(data_source_code, '''') as data_source_code,
            NULLIF(legal_form_code, '''') as legal_form_code,
            NULLIF(status_code, '''') as status_code,
            NULLIF(sector_code, '''') as sector_code,
            NULLIF(unit_size_code, '''') as unit_size_code,
            NULLIF(birth_date, '''') as birth_date_str,
            NULLIF(death_date, '''') as death_date_str,
            NULLIF(valid_from, '''') as valid_from_str, -- Only used if definition has no time_context
            NULLIF(valid_to, '''') as valid_to_str      -- Only used if definition has no time_context
         FROM public.%I WHERE ctid = ANY(%L)
        $$,
        v_job.data_table_name, p_batch_ctids
    );

    v_update_sql := format($$
      UPDATE public.%I SET
            data_source_id = $1,
            legal_form_id = $2,
            status_id = $3,
            sector_id = $4,
            unit_size_id = $5,
            typed_birth_date = $6,
            typed_death_date = $7,
            typed_valid_from = $8,   -- Only set if explicit dates definition
            typed_valid_to = $9,     -- Only set if explicit dates definition
            computed_valid_from = $10, -- Only set if time_context definition
            computed_valid_to = $11,   -- Only set if time_context definition
            last_completed_priority = $12,
            error = NULL,
            state = %L::public.import_data_state -- Keep state as 'analysing' until phase complete
         WHERE ctid = $13
        $$,
        v_job.data_table_name, 'analysing'
    );

    -- Get computed validity dates if time_context is used
    IF v_definition->>'time_context_ident' IS NOT NULL THEN
        SELECT tc.valid_from, tc.valid_to
        INTO v_computed_valid_from, v_computed_valid_to
        FROM public.time_context tc
        WHERE tc.ident = v_definition->>'time_context_ident';
    END IF;

    -- Loop through rows in the batch
    FOR v_row IN EXECUTE v_select_sql
    LOOP
        BEGIN
            -- Perform lookups
            SELECT id INTO v_data_source_id FROM public.data_source WHERE code = v_row.data_source_code;
            SELECT id INTO v_legal_form_id FROM public.legal_form WHERE code = v_row.legal_form_code;
            SELECT id INTO v_status_id FROM public.status WHERE code = v_row.status_code;
            SELECT id INTO v_sector_id FROM public.sector WHERE code = v_row.sector_code;
            SELECT id INTO v_unit_size_id FROM public.unit_size WHERE code = v_row.unit_size_code;

            -- Perform type conversions (handle potential errors)
            DECLARE
                v_birth_date DATE;
                v_death_date DATE;
                v_valid_from DATE;
                v_valid_to DATE;
            BEGIN
                v_birth_date := admin.safe_cast_to_date(v_row.birth_date_str);
                v_death_date := admin.safe_cast_to_date(v_row.death_date_str);

                -- Use computed dates if available, otherwise cast source dates
                IF v_definition->>'time_context_ident' IS NOT NULL THEN
                    v_valid_from := v_computed_valid_from;
                    v_valid_to := v_computed_valid_to;
                ELSE
                    v_valid_from := admin.safe_cast_to_date(v_row.valid_from_str);
                    v_valid_to := admin.safe_cast_to_date(v_row.valid_to_str);
                END IF;

                -- Update the row with looked-up IDs and typed values
                EXECUTE v_update_sql USING
                    v_data_source_id,
                    v_legal_form_id,
                    v_status_id,
                    v_sector_id,
                    v_unit_size_id,
                    v_birth_date,
                    v_death_date,
                    CASE WHEN v_definition->>'time_context_ident' IS NULL THEN v_valid_from ELSE NULL END, -- typed_valid_from
                    CASE WHEN v_definition->>'time_context_ident' IS NULL THEN v_valid_to ELSE NULL END,   -- typed_valid_to
                    CASE WHEN v_definition->>'time_context_ident' IS NOT NULL THEN v_valid_from ELSE NULL END, -- computed_valid_from
                    CASE WHEN v_definition->>'time_context_ident' IS NOT NULL THEN v_valid_to ELSE NULL END,   -- computed_valid_to
                    v_step.priority,
                    v_row.ctid;

            EXCEPTION WHEN others THEN
                 -- Error during type conversion or lookup
                 v_error_count := v_error_count + 1;
                 EXECUTE format('UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = %L',
                                v_job.data_table_name, 'error', SQLERRM, v_step.priority - 1, v_row.ctid);
                 RAISE DEBUG '[Job %] analyse_legal_unit: Error processing row %: %', p_job_id, v_row.ctid, SQLERRM;
            END;

        EXCEPTION WHEN others THEN
            -- Catch-all for unexpected errors during row processing
            v_error_count := v_error_count + 1;
            EXECUTE format('UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = %L',
                           v_job.data_table_name, 'error', 'Unexpected error: ' || SQLERRM, v_step.priority - 1, v_row.ctid);
            RAISE WARNING '[Job %] analyse_legal_unit: Unexpected error processing row %: %', p_job_id, v_row.ctid, SQLERRM;
        END;
    END LOOP;

    RAISE DEBUG '[Job %] analyse_legal_unit: Finished analysis for batch. Errors: %', p_job_id, v_error_count;

END;
$procedure$
```
