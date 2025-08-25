-- Migration: create_temporal_merge_functions
--
-- This migration consolidates the logic from the separate `_update` and `_replace`
-- functions into a single, unified, and more robust implementation. The new
-- functions, `temporal_merge_plan` and `temporal_merge`, use an explicit `p_mode`
-- parameter to control the operational semantics (e.g., `upsert_patch` vs.
-- `replace_only`), providing a clear and maintainable API.
--
-- This consolidation reduces code duplication and aligns the implementation with
-- the final vision for the `sql_saga.temporal_merge` procedure.

BEGIN;

-- This type is dropped and recreated to ensure the new values and order are correct.
-- In a production environment, this would be an ALTER TYPE statement.
DROP TYPE IF EXISTS import.set_operation_mode CASCADE;
CREATE TYPE import.set_operation_mode AS ENUM (
    'upsert_patch',
    'upsert_replace',
    'patch_only',
    'replace_only',
    'insert_only'
);

DO $$ BEGIN
    CREATE TYPE import.set_result_status AS ENUM ('SUCCESS', 'MISSING_TARGET', 'ERROR');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

COMMENT ON TYPE import.set_result_status IS
'Defines the possible return statuses for a row processed by a set-based temporal function.
- SUCCESS: The operation was successfully planned and executed, resulting in a change to the target table.
- MISSING_TARGET: A successful but non-operative outcome. The function executed correctly, but no DML was performed for this row because the target entity for an UPDATE or REPLACE did not exist. This is an expected outcome and a key "semantic hint" for the calling procedure.
- ERROR: A catastrophic failure occurred during the processing of the batch for this row. The transaction was rolled back, and the `error_message` column will be populated.';

DO $$ BEGIN
    CREATE TYPE import.plan_operation_type AS ENUM ('INSERT', 'UPDATE', 'DELETE');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- An internal-only enum that includes the NOOP marker for the planner's internal logic.
DO $$ BEGIN
    CREATE TYPE import.internal_plan_operation_type AS ENUM ('INSERT', 'UPDATE', 'DELETE', 'NOOP');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Defines the structure for a single operation in a temporal execution plan.
DO $$ BEGIN
    CREATE TYPE import.temporal_plan_op AS (
        source_row_ids INTEGER[],
        operation import.plan_operation_type,
        entity_ids JSONB, -- A JSONB object representing the composite key, e.g. {"id": 1} or {"stat_definition_id": 1, "establishment_id": 101}
        old_valid_after DATE,
        new_valid_after DATE,
        new_valid_to DATE,
        data JSONB,
        relation public.allen_interval_relation
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;


-- Unified Planning Function
CREATE OR REPLACE FUNCTION import.temporal_merge_plan(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_entity_id_column_names TEXT[],
    p_source_row_ids INTEGER[],
    p_ephemeral_columns TEXT[],
    p_insert_defaulted_columns TEXT[] DEFAULT '{}',
    p_mode import.set_operation_mode DEFAULT 'upsert_patch'
) RETURNS SETOF import.temporal_plan_op
LANGUAGE plpgsql STABLE AS $temporal_merge_plan$
DECLARE
    v_sql TEXT;
    v_source_data_cols_jsonb_build TEXT;
    v_target_data_cols_jsonb_build TEXT;
    v_entity_id_as_jsonb TEXT;
    v_source_table_regclass REGCLASS;
    v_source_data_payload_expr TEXT;
    v_final_data_payload_expr TEXT;
    v_resolver_ctes TEXT;
    v_resolver_from TEXT;
    v_diff_join_condition TEXT;
    v_plan_source_row_ids_expr TEXT;
BEGIN
    -- Dynamically construct a jsonb object from the entity id columns to use as a single key for partitioning and joining.
    SELECT
        format('jsonb_build_object(%s)', string_agg(format('%L, t.%I', col, col), ', '))
    INTO
        v_entity_id_as_jsonb
    FROM unnest(p_entity_id_column_names) AS col;
    -- Handle resolution of source table OID, which is special for temp tables.
    IF p_source_schema_name = 'pg_temp' THEN
        v_source_table_regclass := to_regclass(p_source_table_name);
    ELSE
        v_source_table_regclass := to_regclass(format('%I.%I', p_source_schema_name, p_source_table_name));
    END IF;

    -- 1. Dynamically get the list of common data columns from SOURCE and TARGET tables.
    WITH source_cols AS (
        SELECT pa.attname
        FROM pg_catalog.pg_attribute pa
        WHERE pa.attrelid = v_source_table_regclass
          AND pa.attnum > 0 AND NOT pa.attisdropped
    ),
    target_cols AS (
        SELECT pa.attname
        FROM pg_catalog.pg_attribute pa
        WHERE pa.attrelid = to_regclass(format('%I.%I', p_target_schema_name, p_target_table_name))
          AND pa.attnum > 0 AND NOT pa.attisdropped
    ),
    common_data_cols AS (
        SELECT s.attname
        FROM source_cols s JOIN target_cols t ON s.attname = t.attname
        WHERE s.attname NOT IN ('row_id', 'valid_after', 'valid_to', 'era_id', 'era_name')
          AND s.attname <> ALL(p_entity_id_column_names)
    )
    SELECT
        format('jsonb_build_object(%s)', string_agg(format('%L, t.%I', attname, attname), ', '))
    INTO
        v_source_data_cols_jsonb_build -- Re-use this variable for the common expression
    FROM
        common_data_cols;

    v_target_data_cols_jsonb_build := v_source_data_cols_jsonb_build; -- Both source and target use the same payload structure
    v_source_data_cols_jsonb_build := COALESCE(v_source_data_cols_jsonb_build, '''{}''::jsonb');
    v_target_data_cols_jsonb_build := COALESCE(v_target_data_cols_jsonb_build, '''{}''::jsonb');

    -- 2. Construct expressions and resolver CTEs based on the mode.
    IF p_mode IN ('upsert_patch', 'patch_only') THEN
        -- In 'patch' modes, data is merged and NULLs from the source are ignored.
        -- Historical data from preceding time slices is inherited into gaps.
        v_source_data_payload_expr := format('jsonb_strip_nulls(%s)', v_source_data_cols_jsonb_build);
        v_resolver_ctes := $$,
segments_with_target_start AS (
    SELECT
        *,
        (t_valid_after = valid_after) as is_target_start_segment
    FROM resolved_atomic_segments_with_payloads
),
payload_groups AS (
    SELECT
        *,
        SUM(CASE WHEN is_target_start_segment THEN 1 ELSE 0 END) OVER (PARTITION BY entity_id ORDER BY valid_after) as payload_group
    FROM segments_with_target_start
),
resolved_atomic_segments_with_inherited_payload AS (
    SELECT
        *,
        FIRST_VALUE(t_data_payload) OVER (PARTITION BY entity_id, payload_group ORDER BY valid_after) as inherited_t_data_payload
    FROM payload_groups
)
$$;
        v_final_data_payload_expr := $$(CASE
            WHEN s_data_payload IS NOT NULL THEN (COALESCE(t_data_payload, inherited_t_data_payload, '{}'::jsonb) || s_data_payload)
            ELSE COALESCE(t_data_payload, inherited_t_data_payload)
        END)$$;
        v_resolver_from := 'resolved_atomic_segments_with_inherited_payload';

    ELSE -- upsert_replace, replace_only
        -- In 'replace' modes, the source data payload overwrites the target. NULLs are meaningful.
        v_source_data_payload_expr := v_source_data_cols_jsonb_build;
        v_resolver_ctes := '';
        -- In `replace` mode, we prioritize the source data (`s_data_payload`). If there is no
        -- source data for a given time segment, we preserve the target data (`t_data_payload`).
        -- This correctly implements the "Temporal Patch" semantic.
        v_final_data_payload_expr := $$COALESCE(s_data_payload, t_data_payload)$$;
        v_resolver_from := 'resolved_atomic_segments_with_payloads';
    END IF;


    -- 3. Conditionally define planner logic based on mode
    IF p_mode IN ('upsert_patch', 'patch_only') THEN
        -- For `patch` mode, we use a complex join condition to find "remainder" slices of
        -- the original timeline and generate UPDATEs for them, avoiding DELETES.
        v_diff_join_condition := $$
           f.f_after = t.t_after
           OR (
               f.f_to = t.t_to AND f.f_data IS NOT DISTINCT FROM t.t_data
               AND NOT EXISTS (
                   SELECT 1 FROM coalesced_final_segments f_inner
                   WHERE f_inner.entity_id = t.t_entity_id AND f_inner.valid_after = t.t_after
               )
           )
        $$;
        -- This expression ensures the source_row_ids from the causal source row are attributed
        -- to the "remainder" slice, which would otherwise have NULL for its source_row_ids.
        v_plan_source_row_ids_expr := $$COALESCE(
            d.f_source_row_ids,
            MAX(d.f_source_row_ids) OVER (PARTITION BY d.entity_id, d.t_after)
        )$$;
    ELSE -- replace modes
        -- For `replace` mode, a simple join is correct. This results in a robust
        -- DELETE and INSERT plan for any timeline splits.
        v_diff_join_condition := 'f.f_after = t.t_after';
        v_plan_source_row_ids_expr := 'd.f_source_row_ids';
    END IF;

    -- 4. Construct and execute the main query to generate the execution plan.
    v_sql := format($SQL$
WITH
source_initial AS (
    SELECT
        t.row_id,
        %1$s as entity_id,
        t.valid_after,
        t.valid_to,
        %2$s AS data_payload
    FROM %3$s.%4$s t
    WHERE (%5$L IS NULL OR t.row_id = ANY(%5$L))
      AND t.valid_after < t.valid_to
),
target_rows AS (
    SELECT
        %1$s as entity_id,
        t.valid_after,
        t.valid_to,
        %9$s AS data_payload
    FROM %6$s.%7$s t
    WHERE (%1$s) IN (SELECT DISTINCT entity_id FROM source_initial)
),
source_rows AS (
    -- Filter the initial source rows based on the operation mode.
    SELECT
        si.row_id as source_row_id,
        si.entity_id,
        si.valid_after,
        si.valid_to,
        si.data_payload
    FROM source_initial si
    WHERE CASE %10$L::import.set_operation_mode
        -- For upsert modes, include all initial source rows.
        WHEN 'upsert_patch' THEN true
        WHEN 'upsert_replace' THEN true
        -- For _only modes, only include rows for entities that already exist in the target.
        WHEN 'patch_only' THEN si.entity_id IN (SELECT tr.entity_id FROM target_rows tr)
        WHEN 'replace_only' THEN si.entity_id IN (SELECT tr.entity_id FROM target_rows tr)
        -- For insert_only, only include rows for entities that DO NOT exist in the target.
        WHEN 'insert_only' THEN si.entity_id NOT IN (SELECT tr.entity_id FROM target_rows tr)
        ELSE false
    END
),
all_rows AS (
    SELECT entity_id, valid_after, valid_to FROM source_rows
    UNION ALL
    SELECT entity_id, valid_after, valid_to FROM target_rows
),
time_points AS (
    SELECT DISTINCT entity_id, point FROM (
        SELECT entity_id, valid_after AS point FROM all_rows
        UNION ALL
        SELECT entity_id, valid_to AS point FROM all_rows
    ) AS points
),
atomic_segments AS (
    SELECT entity_id, point as valid_after, LEAD(point) OVER (PARTITION BY entity_id ORDER BY point) as valid_to
    FROM time_points WHERE point IS NOT NULL
),
resolved_atomic_segments_with_payloads AS (
    SELECT
        seg.entity_id,
        seg.valid_after,
        seg.valid_to,
        t.t_valid_after,
        ( -- Find causal source row
            SELECT sr.source_row_id FROM source_rows sr
            WHERE sr.entity_id = seg.entity_id
              AND (
                  daterange(sr.valid_after, sr.valid_to, '(]') && daterange(seg.valid_after, seg.valid_to, '(]')
                  OR (
                      daterange(sr.valid_after, sr.valid_to, '(]') -|- daterange(seg.valid_after, seg.valid_to, '(]')
                      AND EXISTS (
                          SELECT 1 FROM target_rows tr
                          WHERE tr.entity_id = sr.entity_id
                            AND daterange(sr.valid_after, sr.valid_to, '(]') && daterange(tr.valid_after, tr.valid_to, '(]')
                      )
                  )
              )
            ORDER BY sr.source_row_id LIMIT 1
        ) as source_row_id,
        s.data_payload as s_data_payload,
        t.data_payload as t_data_payload
    FROM atomic_segments seg
    LEFT JOIN LATERAL (
        SELECT tr.data_payload, tr.valid_after as t_valid_after
        FROM target_rows tr
        WHERE tr.entity_id = seg.entity_id
          AND daterange(seg.valid_after, seg.valid_to, '(]') <@ daterange(tr.valid_after, tr.valid_to, '(]')
    ) t ON true
    LEFT JOIN LATERAL (
        SELECT sr.data_payload
        FROM source_rows sr
        WHERE sr.entity_id = seg.entity_id
          AND daterange(seg.valid_after, seg.valid_to, '(]') <@ daterange(sr.valid_after, sr.valid_to, '(]')
    ) s ON true
    WHERE seg.valid_after < seg.valid_to
      AND (s.data_payload IS NOT NULL OR t.data_payload IS NOT NULL) -- Filter out gaps
)
%12$s,
resolved_atomic_segments AS (
    SELECT
        entity_id,
        valid_after,
        valid_to,
        t_valid_after,
        source_row_id,
        %11$s as data_payload,
        CASE WHEN s_data_payload IS NOT NULL THEN 1 ELSE 2 END as priority
    FROM %13$s
),
coalesced_final_segments AS (
    SELECT
        entity_id,
        MIN(valid_after) as valid_after,
        MAX(valid_to) as valid_to,
        data_payload,
        -- Aggregate the source_row_id from each atomic segment into a single array for the merged block.
        array_agg(DISTINCT source_row_id) FILTER (WHERE source_row_id IS NOT NULL) as source_row_ids
    FROM (
        SELECT
            *,
            -- This window function creates a grouping key (segment_group). A new group starts
            -- whenever there is a time gap or a change in the data payload.
            SUM(is_new_segment) OVER (PARTITION BY entity_id ORDER BY valid_after) as segment_group
        FROM (
            SELECT
                ras.*,
                CASE
                    -- A new segment starts if there is a gap between it and the previous one,
                    -- or if the data payload changes. For (exclusive, inclusive] intervals,
                    -- contiguity is defined as the previous `valid_to` being equal to the current `valid_after`.
                    WHEN LAG(ras.valid_to) OVER (PARTITION BY ras.entity_id ORDER BY ras.valid_after) = ras.valid_after
                     AND LAG(ras.data_payload - %8$L::text[]) OVER (PARTITION BY ras.entity_id ORDER BY ras.valid_after) IS NOT DISTINCT FROM (ras.data_payload - %8$L::text[])
                    THEN 0 -- Not a new group (contiguous and same data)
                    ELSE 1 -- Is a new group (time gap or different data)
                END as is_new_segment
            FROM resolved_atomic_segments ras
        ) with_new_segment_flag
    ) with_segment_group
    GROUP BY
        entity_id,
        segment_group,
        data_payload
),

diff AS (
    SELECT
        -- Use COALESCE on entity_id to handle full additions/deletions
        COALESCE(f.f_entity_id, t.t_entity_id) as entity_id,
        f.f_after, f.f_to, f.f_data, f.f_source_row_ids,
        t.t_after, t.t_to, t.t_data,
        -- This function call determines the Allen Interval Relation between the final state and target state segments
        public.allen_get_relation(f.f_after, f.f_to, t.t_after, t.t_to) as relation
    FROM
    (
        SELECT
            entity_id AS f_entity_id,
            valid_after AS f_after,
            valid_to AS f_to,
            data_payload AS f_data,
            source_row_ids AS f_source_row_ids
        FROM coalesced_final_segments
        WHERE data_payload IS NOT NULL
    ) f
    FULL OUTER JOIN
    (
        SELECT
            entity_id as t_entity_id,
            valid_after as t_after,
            valid_to as t_to,
            data_payload as t_data
        FROM target_rows
    ) t
    ON f.f_entity_id = t.t_entity_id AND (%14$s)
),
plan AS (
    SELECT
        %15$s as source_row_ids,
        CASE
            WHEN d.f_data IS NULL THEN 'DELETE'::import.internal_plan_operation_type
            WHEN d.t_data IS NULL THEN 'INSERT'::import.internal_plan_operation_type
            ELSE 'UPDATE'::import.internal_plan_operation_type
        END as operation,
        d.entity_id,
        d.t_after as old_valid_after,
        d.f_after as new_valid_after,
        d.f_to as new_valid_to,
        d.f_data as data,
        d.relation
    FROM diff d
    WHERE d.f_data IS DISTINCT FROM d.t_data
       OR d.f_after IS DISTINCT FROM d.t_after
       OR d.f_to IS DISTINCT FROM d.t_to
)
SELECT
    p.source_row_ids,
    p.operation::text::import.plan_operation_type,
    p.entity_id AS entity_ids,
    p.old_valid_after,
    p.new_valid_after,
    p.new_valid_to,
    p.data,
    p.relation
FROM plan p
WHERE p.operation::text <> 'NOOP'
ORDER BY
    (p.source_row_ids[1]),
    operation DESC, -- DELETEs first
    entity_id,
    COALESCE(new_valid_after, old_valid_after);
$SQL$,
        v_entity_id_as_jsonb,           -- 1
        v_source_data_payload_expr,     -- 2
        p_source_schema_name,           -- 3
        p_source_table_name,            -- 4
        p_source_row_ids,               -- 5
        p_target_schema_name,           -- 6
        p_target_table_name,            -- 7
        p_ephemeral_columns,            -- 8
        v_target_data_cols_jsonb_build, -- 9
        p_mode,                         -- 10
        v_final_data_payload_expr,      -- 11
        v_resolver_ctes,                -- 12
        v_resolver_from,                -- 13
        v_diff_join_condition,          -- 14
        v_plan_source_row_ids_expr      -- 15
    );

    RETURN QUERY EXECUTE v_sql;
END;
$temporal_merge_plan$;


-- Unified Orchestrator Function
CREATE OR REPLACE FUNCTION import.temporal_merge(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_entity_id_column_names TEXT[],
    p_source_row_ids INTEGER[],
    p_ephemeral_columns TEXT[],
    p_insert_defaulted_columns TEXT[] DEFAULT '{}',
    p_mode import.set_operation_mode DEFAULT 'upsert_patch'
)
RETURNS TABLE (
    source_row_id INTEGER,
    target_entity_ids JSONB,
    status import.set_result_status,
    error_message TEXT
)
LANGUAGE plpgsql VOLATILE AS $temporal_merge$
DECLARE
    v_target_table_ident TEXT := format('%I.%I', p_target_schema_name, p_target_table_name);
    v_data_cols_ident TEXT;
    v_data_cols_select TEXT;
    v_update_set_clause TEXT;
    v_all_cols_ident TEXT;
    v_all_cols_select TEXT;
    v_entity_key_join_clause TEXT;
    v_all_source_row_ids INTEGER[];
BEGIN
    -- If p_source_row_ids is NULL, it means "all rows from source". We must fetch them
    -- to provide correct feedback for MISSING_TARGET or ERROR states.
    IF p_source_row_ids IS NULL THEN
        DECLARE
            v_source_table_regclass REGCLASS;
        BEGIN
            IF p_source_schema_name = 'pg_temp' THEN
                v_source_table_regclass := to_regclass(p_source_table_name);
            ELSE
                v_source_table_regclass := to_regclass(format('%I.%I', p_source_schema_name, p_source_table_name));
            END IF;
            EXECUTE format('SELECT array_agg(row_id) FROM %s', v_source_table_regclass) INTO v_all_source_row_ids;
        END;
    ELSE
        v_all_source_row_ids := p_source_row_ids;
    END IF;

    -- Dynamically construct join clause for composite entity key.
    SELECT
        string_agg(format('t.%I = jpr_entity.%I', col, col), ' AND ')
    INTO
        v_entity_key_join_clause
    FROM unnest(p_entity_id_column_names) AS col;
    IF to_regclass('temp_plan') IS NOT NULL THEN
        DROP TABLE temp_plan;
    END IF;
    CREATE TEMP TABLE temp_plan (LIKE import.temporal_plan_op) ON COMMIT DROP;

    BEGIN
        INSERT INTO temp_plan
        SELECT * FROM import.temporal_merge_plan(
            p_target_schema_name, p_target_table_name,
            p_source_schema_name, p_source_table_name,
            p_entity_id_column_names, p_source_row_ids, p_ephemeral_columns,
            p_insert_defaulted_columns, p_mode
        );

        -- Get dynamic column lists for DML, mimicking the planner's introspection logic for consistency.
        DECLARE
            v_source_table_regclass REGCLASS;
        BEGIN
            IF p_source_schema_name = 'pg_temp' THEN
                v_source_table_regclass := to_regclass(p_source_table_name);
            ELSE
                v_source_table_regclass := to_regclass(format('%I.%I', p_source_schema_name, p_source_table_name));
            END IF;

            WITH source_cols AS (
                SELECT pa.attname
                FROM pg_catalog.pg_attribute pa
                WHERE pa.attrelid = v_source_table_regclass AND pa.attnum > 0 AND NOT pa.attisdropped
            ),
            target_cols AS (
                SELECT pa.attname
                FROM pg_catalog.pg_attribute pa
                WHERE pa.attrelid = v_target_table_ident::regclass AND pa.attnum > 0 AND NOT pa.attisdropped
            ),
            common_data_cols AS (
                SELECT s.attname
                FROM source_cols s JOIN target_cols t ON s.attname = t.attname
                WHERE s.attname NOT IN ('row_id', 'valid_after', 'valid_to', 'era_id', 'era_name')
                  AND s.attname <> ALL(p_entity_id_column_names)
            ),
            all_available_cols AS (
                SELECT attname FROM common_data_cols
                UNION ALL
                SELECT unnest(p_entity_id_column_names)
            )
            SELECT
                string_agg(format('%I', attname), ', ') FILTER (WHERE attname <> ALL(p_entity_id_column_names)),
                string_agg(format('jpr_data.%I', attname), ', ') FILTER (WHERE attname <> ALL(p_entity_id_column_names)),
                string_agg(format('%I = jpr_data.%I', attname, attname), ', ') FILTER (WHERE attname <> ALL(p_entity_id_column_names)),
                string_agg(format('%I', attname), ', ') FILTER (WHERE attname <> ALL(p_insert_defaulted_columns)),
                string_agg(format('jpr_all.%I', attname), ', ') FILTER (WHERE attname <> ALL(p_insert_defaulted_columns))
            INTO
                v_data_cols_ident,
                v_data_cols_select,
                v_update_set_clause,
                v_all_cols_ident,
                v_all_cols_select
            FROM all_available_cols;
        END;

        SET CONSTRAINTS ALL DEFERRED;

        -- INSERT -> UPDATE -> DELETE order is critical for sql_saga compatibility.
        -- 1. Execute INSERT operations
        IF v_all_cols_ident IS NOT NULL THEN
             EXECUTE format($$ INSERT INTO %1$s (%2$s, valid_after, valid_to)
                SELECT %3$s, p.new_valid_after, p.new_valid_to
                FROM temp_plan p, LATERAL jsonb_populate_record(null::%1$s, p.entity_ids || p.data) AS jpr_all
                WHERE p.operation = 'INSERT';
            $$, v_target_table_ident, v_all_cols_ident, v_all_cols_select);
        ELSE
             EXECUTE format($$ INSERT INTO %1$s (valid_after, valid_to)
                SELECT p.new_valid_after, p.new_valid_to FROM temp_plan p WHERE p.operation = 'INSERT';
            $$, v_target_table_ident);
        END IF;

        -- 2. Execute UPDATE operations
        IF v_update_set_clause IS NOT NULL THEN
            EXECUTE format($$ UPDATE %1$s t SET valid_after = p.new_valid_after, valid_to = p.new_valid_to, %2$s
                FROM temp_plan p,
                     LATERAL jsonb_populate_record(null::%1$s, p.data) AS jpr_data,
                     LATERAL jsonb_populate_record(null::%1$s, p.entity_ids) AS jpr_entity
                WHERE p.operation = 'UPDATE' AND %3$s AND t.valid_after = p.old_valid_after;
            $$, v_target_table_ident, v_update_set_clause, v_entity_key_join_clause);
        ELSE
            EXECUTE format($$ UPDATE %1$s t SET valid_after = p.new_valid_after, valid_to = p.new_valid_to
                FROM temp_plan p, LATERAL jsonb_populate_record(null::%1$s, p.entity_ids) AS jpr_entity
                WHERE p.operation = 'UPDATE' AND %2$s AND t.valid_after = p.old_valid_after;
            $$, v_target_table_ident, v_entity_key_join_clause);
        END IF;

        -- 3. Execute DELETE operations
        EXECUTE format($$ DELETE FROM %1$s t
            USING temp_plan p, LATERAL jsonb_populate_record(null::%1$s, p.entity_ids) AS jpr_entity
            WHERE p.operation = 'DELETE' AND %2$s AND t.valid_after = p.old_valid_after;
        $$, v_target_table_ident, v_entity_key_join_clause);

        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        IF to_regclass('temp_plan') IS NOT NULL THEN DROP TABLE temp_plan; END IF;
        RETURN QUERY
            SELECT r.row_id, '[]'::JSONB, 'ERROR'::import.set_result_status, SQLERRM
            FROM unnest(COALESCE(v_all_source_row_ids, ARRAY[]::INTEGER[])) AS r(row_id);
        RETURN;
    END;

    RETURN QUERY
        SELECT
            s.row_id as source_row_id,
            jsonb_agg(DISTINCT p.entity_ids) FILTER (WHERE p.entity_ids IS NOT NULL) AS target_entity_ids,
            'SUCCESS'::import.set_result_status,
            NULL::TEXT
        FROM temp_plan p, unnest(p.source_row_ids) AS s(row_id)
        GROUP BY s.row_id
        UNION ALL
        SELECT
            r.row_id,
            '[]'::jsonb,
            'MISSING_TARGET'::import.set_result_status,
            NULL::TEXT
        FROM unnest(COALESCE(v_all_source_row_ids, ARRAY[]::INTEGER[])) AS r(row_id)
        WHERE NOT EXISTS (SELECT 1 FROM temp_plan p, unnest(p.source_row_ids) s(id) WHERE s.id = r.row_id);
END;
$temporal_merge$;

COMMENT ON FUNCTION import.temporal_merge IS
'Orchestrates a set-based temporal merge operation. It generates a plan using temporal_merge_plan and then executes it.';


COMMIT;
