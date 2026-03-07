```sql
CREATE OR REPLACE PROCEDURE import.analyse_power_group_link(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_step_priority INT;
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition
    FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    -- Only run for legal_relationship mode
    IF v_definition.mode != 'legal_relationship' THEN
        RAISE DEBUG '[Job %] analyse_power_group_link: Skipping, mode is %', p_job_id, v_definition.mode;
        -- Advance last_completed_priority for all rows
        SELECT * INTO v_step
        FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
        WHERE code = p_step_code;
        EXECUTE format($$
            UPDATE public.%I SET last_completed_priority = %L WHERE last_completed_priority < %L
        $$, v_data_table_name, v_step.priority, v_step.priority);
        RETURN;
    END IF;

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = p_step_code;
    v_step_priority := v_step.priority;

    RAISE DEBUG '[Job %] analyse_power_group_link: Computing power group clusters (holistic)', p_job_id;

    -- Build complete relationship graph: UNION of existing base table rows + new rows from data table.
    -- Then compute clusters using recursive CTE (connected components).
    -- Finally, find/assign derived_power_group_id for each cluster and populate data table rows.
    EXECUTE format($sql$
        WITH RECURSIVE
        -- Combined graph: existing relationships + new ones from import data table
        all_relationships AS (
            -- Existing relationships from base table
            SELECT lr.influencing_id, lr.influenced_id, lr.valid_range, lr.derived_power_group_id
            FROM public.legal_relationship AS lr
            UNION ALL
            -- New relationships from data table (where action = 'use')
            SELECT dt.influencing_id, dt.influenced_id,
                   daterange(dt.valid_from, dt.valid_until) AS valid_range,
                   NULL::integer AS derived_power_group_id
            FROM public.%1$I AS dt
            WHERE dt.action = 'use'
        ),
        -- Compute hierarchy: find root legal units and traverse down
        hierarchy AS (
            -- Root legal units: have controlling children but no controlling parent
            SELECT
                lu.id AS legal_unit_id,
                lu.valid_range,
                lu.id AS root_legal_unit_id,
                1 AS power_level,
                ARRAY[lu.id] AS path,
                FALSE AS is_cycle
            FROM public.legal_unit AS lu
            WHERE EXISTS (
                SELECT 1 FROM all_relationships AS ar
                WHERE ar.influencing_id = lu.id AND ar.valid_range && lu.valid_range
            )
            AND NOT EXISTS (
                SELECT 1 FROM all_relationships AS ar
                WHERE ar.influenced_id = lu.id AND ar.valid_range && lu.valid_range
            )
            UNION ALL
            SELECT
                ar.influenced_id AS legal_unit_id,
                influenced_lu.valid_range * ar.valid_range * h.valid_range AS valid_range,
                h.root_legal_unit_id,
                h.power_level + 1 AS power_level,
                h.path || ar.influenced_id AS path,
                ar.influenced_id = ANY(h.path) AS is_cycle
            FROM hierarchy AS h
            JOIN all_relationships AS ar
                ON ar.influencing_id = h.legal_unit_id
                AND ar.valid_range && h.valid_range
            JOIN public.legal_unit AS influenced_lu
                ON influenced_lu.id = ar.influenced_id
                AND influenced_lu.valid_range && ar.valid_range
            WHERE NOT h.is_cycle AND h.power_level < 100
        ),
        -- Distinct clusters by root
        clusters AS (
            SELECT DISTINCT root_legal_unit_id FROM hierarchy WHERE NOT is_cycle
        ),
        -- Find existing power_group for each cluster (via legal_relationship base table)
        cluster_pg AS (
            SELECT c.root_legal_unit_id,
                   (SELECT lr.derived_power_group_id
                    FROM public.legal_relationship AS lr
                    JOIN hierarchy AS h ON (lr.influencing_id = h.legal_unit_id OR lr.influenced_id = h.legal_unit_id)
                        AND lr.valid_range && h.valid_range
                    WHERE h.root_legal_unit_id = c.root_legal_unit_id
                      AND lr.derived_power_group_id IS NOT NULL
                    LIMIT 1) AS existing_power_group_id
            FROM clusters AS c
        ),
        -- Map each data table row to its cluster root
        row_clusters AS (
            SELECT dt.row_id,
                   h.root_legal_unit_id
            FROM public.%1$I AS dt
            JOIN hierarchy AS h ON (dt.influencing_id = h.legal_unit_id OR dt.influenced_id = h.legal_unit_id)
            WHERE dt.action = 'use'
        )
        UPDATE public.%1$I AS dt
        SET cluster_root_legal_unit_id = rc.root_legal_unit_id,
            derived_power_group_id = cpg.existing_power_group_id
        FROM row_clusters AS rc
        JOIN cluster_pg AS cpg ON cpg.root_legal_unit_id = rc.root_legal_unit_id
        WHERE dt.row_id = rc.row_id
    $sql$, v_data_table_name);

    -- Advance last_completed_priority for all rows
    EXECUTE format($$
        UPDATE public.%I SET last_completed_priority = %L WHERE last_completed_priority < %L
    $$, v_data_table_name, v_step_priority, v_step_priority);

    RAISE DEBUG '[Job %] analyse_power_group_link: Complete', p_job_id;
END;
$procedure$
```
