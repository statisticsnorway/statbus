```sql
CREATE OR REPLACE PROCEDURE admin.process_contact(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$ -- Function name remains the same, step name changed
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    v_edit_by_user_id INT;
    v_timestamp TIMESTAMPTZ := clock_timestamp();
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_contact (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_definition := v_job.definition_snapshot->'import_definition'; -- Read from snapshot column

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Find the step details
    SELECT * INTO v_step FROM public.import_step WHERE code = 'contact'; -- Use new step name
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] contact step not found', p_job_id;
    END IF;

    -- Determine operation type and user ID
    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    v_edit_by_user_id := v_job.user_id;

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Step 1: Unpivot and Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        ctid TID,
        legal_unit_id INT,
        establishment_id INT,
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        contact_type public.contact_info_type,
        contact_value TEXT,
        existing_contact_id INT,
        PRIMARY KEY (ctid, contact_type) -- Ensure uniqueness per row/type
    ) ON COMMIT DROP;

    v_sql := format('
        INSERT INTO temp_batch_data (
            ctid, legal_unit_id, establishment_id, valid_from, valid_to, data_source_id, contact_type, contact_value
        )
        SELECT
            ctid, legal_unit_id, establishment_id,
            COALESCE(typed_valid_from, computed_valid_from),
            COALESCE(typed_valid_to, computed_valid_to),
            data_source_id,
            unnested.type, unnested.value
        FROM public.%I dt,
        LATERAL (VALUES
            (''web'', dt.web_address),
            (''email'', dt.email_address),
            (''phone'', dt.phone_number),
            (''landline'', dt.landline),
            (''mobile'', dt.mobile_number),
            (''fax'', dt.fax_number)
        ) AS unnested(type, value)
        WHERE dt.ctid = ANY(%L) AND unnested.value IS NOT NULL;
    ', v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] process_contact: Fetching and unpivoting batch data: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Determine existing contact IDs
    v_sql := format('
        UPDATE temp_batch_data tbd SET
            existing_contact_id = ci.id
        FROM public.contact ci -- Use contact table
        WHERE ci.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND ci.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
          -- Assuming only one contact record per unit (enforced by contact table constraints?)
    ');
    RAISE DEBUG '[Job %] process_contact: Determining existing IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Perform Batch INSERT into contact_info_era (Leveraging Trigger)
    BEGIN
        -- Unpivot and insert/update contact details directly into contact table (non-temporal)
        -- Use ON CONFLICT to handle upsert based on the unit link
        v_sql := format('
            WITH unpivoted_data AS (
                SELECT
                    tbd.ctid,
                    tbd.existing_contact_id,
                    tbd.legal_unit_id,
                    tbd.establishment_id,
                    tbd.data_source_id,
                    jsonb_object_agg(tbd.contact_type, tbd.contact_value) as contact_details
                FROM temp_batch_data tbd
                GROUP BY tbd.ctid, tbd.existing_contact_id, tbd.legal_unit_id, tbd.establishment_id, tbd.data_source_id
            )
            INSERT INTO public.contact (
                id, legal_unit_id, establishment_id, data_source_id,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                edit_by_user_id, edit_at
            )
            SELECT
                up.existing_contact_id, up.legal_unit_id, up.establishment_id, up.data_source_id,
                up.contact_details->>''web'', up.contact_details->>''email'', up.contact_details->>''phone'',
                up.contact_details->>''landline'', up.contact_details->>''mobile'', up.contact_details->>''fax'',
                dt.edit_by_user_id, dt.edit_at -- Read from _data table via temp table join
            FROM unpivoted_data up
            JOIN public.%I dt ON up.ctid = dt.ctid -- Join to get audit info
            WHERE
                CASE %L::public.import_strategy
                    WHEN ''insert_only'' THEN up.existing_contact_id IS NULL
                    WHEN ''update_only'' THEN up.existing_contact_id IS NOT NULL
                    WHEN ''upsert'' THEN TRUE
                END
            ON CONFLICT (legal_unit_id) WHERE legal_unit_id IS NOT NULL DO UPDATE SET
                web_address = EXCLUDED.web_address, email_address = EXCLUDED.email_address, phone_number = EXCLUDED.phone_number,
                landline = EXCLUDED.landline, mobile_number = EXCLUDED.mobile_number, fax_number = EXCLUDED.fax_number,
                data_source_id = EXCLUDED.data_source_id, edit_by_user_id = EXCLUDED.edit_by_user_id, edit_at = EXCLUDED.edit_at
            ON CONFLICT (establishment_id) WHERE establishment_id IS NOT NULL DO UPDATE SET
                 web_address = EXCLUDED.web_address, email_address = EXCLUDED.email_address, phone_number = EXCLUDED.phone_number,
                landline = EXCLUDED.landline, mobile_number = EXCLUDED.mobile_number, fax_number = EXCLUDED.fax_number,
                data_source_id = EXCLUDED.data_source_id, edit_by_user_id = EXCLUDED.edit_by_user_id, edit_at = EXCLUDED.edit_at
            RETURNING id, legal_unit_id, establishment_id; -- Return needed info to link back
        ', v_data_table_name, v_strategy); -- Removed v_edit_by_user_id, v_timestamp

        RAISE DEBUG '[Job %] process_contact: Performing batch UPSERT into contact: %', p_job_id, v_sql;

        -- Execute and update _data table in one go
        v_sql := format('
            WITH upserted_contacts AS ( %s ),
            link_lookup AS (
                 SELECT DISTINCT ON (ctid) tbd.ctid, uc.id as contact_id
                 FROM temp_batch_data tbd
                 JOIN upserted_contacts uc ON uc.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
                                          AND uc.establishment_id IS NOT DISTINCT FROM tbd.establishment_id
                 WHERE CASE %L::public.import_strategy
                         WHEN ''insert_only'' THEN tbd.existing_contact_id IS NULL
                         WHEN ''update_only'' THEN tbd.existing_contact_id IS NOT NULL
                         WHEN ''upsert'' THEN TRUE
                       END
            )
            UPDATE public.%I dt SET
                contact_id = ll.contact_id, -- Use singular contact_id
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM link_lookup ll
            WHERE dt.ctid = ll.ctid AND dt.state != %L;
        ', v_sql, v_strategy, v_data_table_name, v_step.priority, 'importing', 'error');

        RAISE DEBUG '[Job %] process_contact: Executing UPSERT and updating _data table: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Rows updated in _data table

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_contact: Error during batch operation: %', p_job_id, error_message;
        -- Mark the entire batch as error in _data table
        v_sql := format('UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = ANY(%L)',
                       v_data_table_name, 'error', jsonb_build_object('batch_error', error_message), v_step.priority - 1, p_batch_ctids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        -- Update job error
        UPDATE public.import_job SET error = jsonb_build_object('process_contact_error', error_message) WHERE id = p_job_id;
    END;

     -- Update priority for rows that didn't have any contact info (were skipped)
     v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.ctid = ANY(%L) AND dt.state != %L
          AND web_address IS NULL AND email_address IS NULL AND phone_number IS NULL
          AND landline IS NULL AND mobile_number IS NULL AND fax_number IS NULL;
    ', v_data_table_name, v_step.priority, p_batch_ctids, 'error');
    EXECUTE v_sql;

    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_contact (Batch): Finished operation for batch. Initial batch size: %. Errors (estimated): %', p_job_id, array_length(p_batch_ctids, 1), v_error_count;
END;
$procedure$
```
