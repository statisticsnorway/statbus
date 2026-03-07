```sql
CREATE OR REPLACE PROCEDURE import.helper_process_external_idents(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_data_table_name TEXT;
    v_job_mode public.import_mode;
    v_ident_data_cols JSONB;
    v_step public.import_step;
    v_col_rec RECORD;
    v_sql TEXT;
    v_unit_id_col_name TEXT;
    v_unit_type TEXT;
    v_rows_affected INT;
    v_ident_type_rec RECORD;
BEGIN
    RAISE DEBUG '[Job %] helper_process_external_idents (Batch): Starting for batch_seq % for step %', p_job_id, p_batch_seq, p_step_code;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Determine unit type and ID column from job mode
    IF v_job_mode = 'legal_unit' THEN
        v_unit_type := 'legal_unit';
        v_unit_id_col_name := 'legal_unit_id';
    ELSIF v_job_mode IN ('establishment_formal', 'establishment_informal') THEN
        v_unit_type := 'establishment';
        v_unit_id_col_name := 'establishment_id';
    ELSE
        RAISE DEBUG '[Job %] helper_process_external_idents: Job mode is ''%'', which does not have external identifiers processed by this step. Skipping.', p_job_id, v_job_mode;
        RETURN;
    END IF;

    -- Get relevant columns for the external_idents step from snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'external_idents';
    SELECT jsonb_agg(value) INTO v_ident_data_cols
    FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') value
    WHERE (value->>'step_id')::int = v_step.id 
      AND value->>'purpose' IN ('source_input', 'internal');

    IF v_ident_data_cols IS NULL OR jsonb_array_length(v_ident_data_cols) = 0 THEN
        RAISE DEBUG '[Job %] helper_process_external_idents: No external ident columns found for step. Skipping.', p_job_id;
        RETURN;
    END IF;

    -- ============================================================================
    -- Process REGULAR identifiers (single column per type, uses ident field)
    -- ============================================================================
    FOR v_ident_type_rec IN
        SELECT eit.id, eit.code, eit.shape
        FROM public.external_ident_type_active eit
        WHERE eit.shape = 'regular'
        ORDER BY eit.priority
    LOOP
        -- Check if we have a column for this type
        IF NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(v_ident_data_cols) value
            WHERE value->>'column_name' = v_ident_type_rec.code || '_raw'
        ) THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] helper_process_external_idents: Processing regular identifier type: %', p_job_id, v_ident_type_rec.code;
        
        v_sql := format(
                $SQL$
                MERGE INTO public.external_ident AS t
                USING (
                    SELECT DISTINCT ON (dt.founding_row_id, dt.%3$I)
                        dt.founding_row_id,
                        dt.%1$I AS unit_id,
                        dt.edit_by_user_id,
                        dt.edit_at,
                        dt.edit_comment,
                        %2$L::integer AS type_id,
                        dt.%3$I AS ident_value
                    FROM public.%4$I dt
                    WHERE dt.batch_seq = $1
                      AND dt.action = 'use'
                      AND dt.%1$I IS NOT NULL
                      AND NULLIF(dt.%3$I, '') IS NOT NULL
                    ORDER BY dt.founding_row_id, dt.%3$I, dt.row_id
                ) AS s
                ON (t.type_id = s.type_id AND t.ident = s.ident_value)
                WHEN MATCHED AND (
                    t.legal_unit_id IS DISTINCT FROM (CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END) OR
                    t.establishment_id IS DISTINCT FROM (CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END)
                ) THEN
                    UPDATE SET
                        legal_unit_id = CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        establishment_id = CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        enterprise_id = NULL,
                        power_group_id = NULL,
                        edit_by_user_id = s.edit_by_user_id,
                        edit_at = s.edit_at,
                        edit_comment = s.edit_comment
                WHEN NOT MATCHED THEN
                    INSERT (legal_unit_id, establishment_id, type_id, ident, edit_by_user_id, edit_at, edit_comment)
                    VALUES (
                        CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        s.type_id,
                        s.ident_value,
                        s.edit_by_user_id,
                        s.edit_at,
                        s.edit_comment
                    );
                $SQL$,
                v_unit_id_col_name,                      -- %1$I
                v_ident_type_rec.id,                    -- %2$L
                v_ident_type_rec.code || '_raw',        -- %3$I
                v_data_table_name,                      -- %4$I
                v_unit_type                             -- %5$L
            );
        
        RAISE DEBUG '[Job %] helper_process_external_idents: Regular MERGE SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        RAISE DEBUG '[Job %] helper_process_external_idents: Merged % rows for regular identifier type %.', p_job_id, v_rows_affected, v_ident_type_rec.code;
    END LOOP;

    -- ============================================================================
    -- Process HIERARCHICAL identifiers (uses idents field with ltree)
    -- ============================================================================
    FOR v_ident_type_rec IN
        SELECT eit.id, eit.code, eit.shape, eit.labels
        FROM public.external_ident_type_active eit
        WHERE eit.shape = 'hierarchical'
          AND eit.labels IS NOT NULL
        ORDER BY eit.priority
    LOOP
        -- Check if we have the path column for this type
        IF NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(v_ident_data_cols) value
            WHERE value->>'column_name' = v_ident_type_rec.code || '_path'
        ) THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] helper_process_external_idents: Processing hierarchical identifier type: % (path column: %_path)', 
            p_job_id, v_ident_type_rec.code, v_ident_type_rec.code;
        
        -- For hierarchical identifiers, we use the {code}_path column which contains the ltree value
        -- The MERGE matches on t.idents = s.idents_value (both ltree)
        v_sql := format(
                $SQL$
                MERGE INTO public.external_ident AS t
                USING (
                    SELECT DISTINCT ON (dt.founding_row_id, dt.%3$I)
                        dt.founding_row_id,
                        dt.%1$I AS unit_id,
                        dt.edit_by_user_id,
                        dt.edit_at,
                        dt.edit_comment,
                        %2$L::integer AS type_id,
                        dt.%3$I AS idents_value
                    FROM public.%4$I dt
                    WHERE dt.batch_seq = $1
                      AND dt.action = 'use'
                      AND dt.%1$I IS NOT NULL
                      AND dt.%3$I IS NOT NULL
                    ORDER BY dt.founding_row_id, dt.%3$I, dt.row_id
                ) AS s
                ON (t.type_id = s.type_id AND t.idents = s.idents_value)
                WHEN MATCHED AND (
                    t.legal_unit_id IS DISTINCT FROM (CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END) OR
                    t.establishment_id IS DISTINCT FROM (CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END)
                ) THEN
                    UPDATE SET
                        legal_unit_id = CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        establishment_id = CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        enterprise_id = NULL,
                        power_group_id = NULL,
                        edit_by_user_id = s.edit_by_user_id,
                        edit_at = s.edit_at,
                        edit_comment = s.edit_comment
                WHEN NOT MATCHED THEN
                    INSERT (legal_unit_id, establishment_id, type_id, idents, edit_by_user_id, edit_at, edit_comment)
                    VALUES (
                        CASE WHEN %5$L = 'legal_unit' THEN s.unit_id ELSE NULL END,
                        CASE WHEN %5$L = 'establishment' THEN s.unit_id ELSE NULL END,
                        s.type_id,
                        s.idents_value,
                        s.edit_by_user_id,
                        s.edit_at,
                        s.edit_comment
                    );
                $SQL$,
                v_unit_id_col_name,                       -- %1$I
                v_ident_type_rec.id,                     -- %2$L
                v_ident_type_rec.code || '_path',        -- %3$I (the ltree path column)
                v_data_table_name,                       -- %4$I
                v_unit_type                              -- %5$L
            );
        
        RAISE DEBUG '[Job %] helper_process_external_idents: Hierarchical MERGE SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        RAISE DEBUG '[Job %] helper_process_external_idents: Merged % rows for hierarchical identifier type %.', p_job_id, v_rows_affected, v_ident_type_rec.code;
    END LOOP;
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[Job %] helper_process_external_idents: Error during batch operation: %', p_job_id, SQLERRM;
    RAISE;
END;
$procedure$
```
