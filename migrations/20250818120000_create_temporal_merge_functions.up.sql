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
    v_resolved_data_payload_expr TEXT;
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
          AND s.attname <> ALL(p_insert_defaulted_columns)
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

    -- 2. Construct expressions based on the mode to handle NULLs correctly.
    IF p_mode IN ('upsert_patch', 'patch_only') THEN
        v_source_data_payload_expr := format('jsonb_strip_nulls(%s)', v_source_data_cols_jsonb_build);
        v_resolved_data_payload_expr := $$(CASE WHEN s.data_payload IS NOT NULL THEN (COALESCE(t.data_payload, '{}'::jsonb) || s.data_payload) ELSE t.data_payload END)$$;
    ELSE -- upsert_replace, replace_only
        v_source_data_payload_expr := v_source_data_cols_jsonb_build;
        v_resolved_data_payload_expr := $$COALESCE(s.data_payload, t.data_payload)$$;
    END IF;


    -- 3. Construct and execute the main query to generate the execution plan.
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
resolved_atomic_segments AS (
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
        %11$s as data_payload,
        CASE WHEN s.data_payload IS NOT NULL THEN 1 ELSE 2 END as priority
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
),
coalesced_timeline_segments AS (
    SELECT
        entity_id,
        MIN(valid_after) as valid_after,
        MAX(valid_to) as valid_to,
        (array_agg(data_payload ORDER BY priority, valid_after DESC))[1] as data_payload,
        (array_agg(source_row_id ORDER BY priority, valid_after DESC))[1] as representative_source_row_id,
        array_agg(DISTINCT source_row_id) FILTER (WHERE source_row_id IS NOT NULL) as source_row_ids,
        (array_agg(t_valid_after ORDER BY valid_after) FILTER (WHERE t_valid_after IS NOT NULL))[1] as candidate_anchor,
        COUNT(*) as segments_in_group
    FROM (
        SELECT *,
            SUM(CASE WHEN is_new_group THEN 1 ELSE 0 END) OVER (PARTITION BY entity_id ORDER BY valid_after) as group_id
        FROM (
            SELECT fss.*,
                COALESCE(
                    (LAG(fss.data_payload - %8$L::text[], 1) OVER (PARTITION BY fss.entity_id ORDER BY fss.valid_after) IS DISTINCT FROM (fss.data_payload - %8$L::text[]))
                    OR
                    (LAG(fss.valid_to, 1) OVER (PARTITION BY fss.entity_id ORDER BY fss.valid_after) IS DISTINCT FROM fss.valid_after),
                    true
                ) as is_new_group
            FROM resolved_atomic_segments fss
        ) with_new_group_flag
    ) with_group_id
    GROUP BY entity_id, group_id
),
anchored_timeline_segments AS (
    SELECT f.*,
        CASE
            WHEN f.valid_after = f.candidate_anchor THEN f.candidate_anchor
            WHEN f.valid_after != f.candidate_anchor AND f.candidate_anchor IS NOT NULL AND f.segments_in_group > 1 THEN f.candidate_anchor
            ELSE NULL
        END as anchor_t_valid_after
    FROM coalesced_timeline_segments f
),
diff AS (
    SELECT
        f.entity_id as f_entity_id, f.valid_after as f_after, f.valid_to as f_to, f.data_payload as f_data, f.representative_source_row_id as f_representative_source_row_id, f.source_row_ids as f_source_row_ids,
        t.entity_id as t_entity_id, t.valid_after as t_after, t.valid_to as t_to, t.data_payload as t_data,
        ROW_NUMBER() OVER(PARTITION BY t.entity_id, t.valid_after ORDER BY f.valid_after) as update_candidate_rank
    FROM anchored_timeline_segments f
    FULL OUTER JOIN target_rows t ON f.entity_id = t.entity_id AND f.anchor_t_valid_after = t.valid_after
    WHERE f.entity_id IS NULL -- A row from target_rows was deleted
       OR t.entity_id IS NULL -- A row from the final state is new
       OR (f.data_payload - %8$L::text[]) IS DISTINCT FROM (t.data_payload - %8$L::text[]) -- A row was updated (data changed)
       OR f.valid_to IS DISTINCT FROM t.valid_to -- A row was updated (timeline changed)
       OR f.valid_after IS DISTINCT FROM t.valid_after -- A row was updated (timeline changed, e.g. a merge)
),
plan AS (
    SELECT
        d.source_row_ids,
        d.representative_source_row_id,
        CASE
            WHEN d.f_after IS NULL THEN 'DELETE'::import.internal_plan_operation_type
            WHEN d.t_after IS NULL THEN 'INSERT'::import.internal_plan_operation_type
            WHEN d.update_candidate_rank > 1 THEN 'INSERT'::import.internal_plan_operation_type
            WHEN d.operation_type = 'UPDATE' THEN 'UPDATE'::import.internal_plan_operation_type
            ELSE 'NOOP'::import.internal_plan_operation_type
        END as operation,
        d.entity_id,
        d.old_valid_after,
        d.new_valid_after,
        d.new_valid_to,
        d.data
    FROM (
        SELECT
            COALESCE(f_source_row_ids, ARRAY[(SELECT s.source_row_id FROM source_rows s WHERE s.entity_id = COALESCE(f_entity_id, t_entity_id) AND (daterange(s.valid_after, s.valid_to, '(]') && daterange(COALESCE(f_after, t_after), COALESCE(f_to, t_to), '(]') OR daterange(s.valid_after, s.valid_to, '(]') -|- daterange(COALESCE(f_after, t_after), COALESCE(f_to, t_to), '(]')) ORDER BY s.source_row_id LIMIT 1)]) AS source_row_ids,
            COALESCE(f_representative_source_row_id, (SELECT s.source_row_id FROM source_rows s WHERE s.entity_id = COALESCE(f_entity_id, t_entity_id) AND (daterange(s.valid_after, s.valid_to, '(]') && daterange(COALESCE(f_after, t_after), COALESCE(f_to, t_to), '(]') OR daterange(s.valid_after, s.valid_to, '(]') -|- daterange(COALESCE(f_after, t_after), COALESCE(f_to, t_to), '(]')) ORDER BY s.source_row_id LIMIT 1)) AS representative_source_row_id,
            COALESCE(f_entity_id, t_entity_id) as entity_id,
            CASE WHEN update_candidate_rank > 1 THEN NULL ELSE t_after END as old_valid_after,
            f_after as new_valid_after,
            f_to as new_valid_to,
            f_data as data,
            f_entity_id, t_entity_id, t_after,
            update_candidate_rank,
            f_after as f_after,
            CASE
                WHEN (f_data - %8$L::text[]) IS DISTINCT FROM (t_data - %8$L::text[]) THEN 'UPDATE'
                WHEN f_to IS DISTINCT FROM t_to THEN 'UPDATE'
                WHEN f_after IS DISTINCT FROM t_after THEN 'UPDATE'
                ELSE 'NOOP'
            END as operation_type
        FROM diff
    ) d
)
SELECT
    p.source_row_ids,
    p.operation::text::import.plan_operation_type,
    p.entity_id AS entity_ids,
    p.old_valid_after,
    p.new_valid_after,
    p.new_valid_to,
    p.data,
    rel.relation
FROM plan p
LEFT JOIN LATERAL (
    SELECT rel.relation FROM (
        SELECT
            (CASE
                WHEN s.valid_after = t.valid_after AND s.valid_to = t.valid_to THEN 'equals'
                WHEN s.valid_after = t.valid_after AND s.valid_to < t.valid_to THEN 'starts'
                WHEN s.valid_after = t.valid_after AND s.valid_to > t.valid_to THEN 'started_by'
                WHEN s.valid_after > t.valid_after AND s.valid_to = t.valid_to THEN 'finishes'
                WHEN s.valid_after < t.valid_after AND s.valid_to = t.valid_to THEN 'finished_by'
                WHEN s.valid_after > t.valid_after AND s.valid_to < t.valid_to THEN 'during'
                WHEN s.valid_after < t.valid_after AND s.valid_to > t.valid_to THEN 'contains'
                WHEN s.valid_to = t.valid_after THEN 'meets'
                WHEN s.valid_after = t.valid_to THEN 'met_by'
                WHEN s.valid_after < t.valid_after AND s.valid_to > t.valid_after AND s.valid_to < t.valid_to THEN 'overlaps'
                WHEN t.valid_after < s.valid_after AND t.valid_to > s.valid_after AND t.valid_to < s.valid_to THEN 'overlapped_by'
                WHEN s.valid_to < t.valid_after THEN 'precedes'
                WHEN s.valid_after > t.valid_to THEN 'preceded_by'
            END)::public.allen_interval_relation as relation,
            GREATEST(
                CASE WHEN t.valid_to = 'infinity' THEN -2147483647 ELSE s.valid_after - t.valid_to END,
                CASE WHEN s.valid_to = 'infinity' THEN -2147483647 ELSE t.valid_after - s.valid_to END
            ) as distance
        FROM source_rows s
        JOIN target_rows t ON s.entity_id = t.entity_id
        WHERE s.source_row_id = p.representative_source_row_id
    ) rel
    ORDER BY rel.distance
    LIMIT 1
) rel ON p.representative_source_row_id IS NOT NULL
WHERE p.operation::text <> 'NOOP'
ORDER BY
    representative_source_row_id,
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
        v_resolved_data_payload_expr    -- 11
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
BEGIN
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

        -- Get dynamic column lists for DML.
        WITH target_cols AS (
            SELECT c.column_name
            FROM information_schema.columns c
            LEFT JOIN (
                SELECT array_agg(a.attname) as cols
                FROM   pg_index i
                JOIN   pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
                WHERE  i.indrelid = v_target_table_ident::regclass
                AND    i.indisprimary
            ) pk ON true
            WHERE c.table_schema = p_target_schema_name
              AND c.table_name = p_target_table_name
              AND c.column_name NOT IN ('valid_after', 'valid_to', 'era_id', 'era_name')
              AND (pk.cols IS NULL OR c.column_name <> ALL(pk.cols) OR c.column_name = ANY(p_entity_id_column_names))
            ORDER BY c.ordinal_position
        )
        SELECT
            string_agg(format('%I', column_name), ', ') FILTER (WHERE column_name <> ALL(p_entity_id_column_names)),
            string_agg(format('jpr_data.%I', column_name), ', ') FILTER (WHERE column_name <> ALL(p_entity_id_column_names)),
            string_agg(format('%I = jpr_data.%I', column_name, column_name), ', ') FILTER (WHERE column_name <> ALL(p_entity_id_column_names)),
            string_agg(format('%I', column_name), ', ') FILTER (WHERE column_name <> ALL(p_insert_defaulted_columns)),
            string_agg(format('jpr_all.%I', column_name), ', ') FILTER (WHERE column_name <> ALL(p_insert_defaulted_columns))
        INTO
            v_data_cols_ident,
            v_data_cols_select,
            v_update_set_clause,
            v_all_cols_ident,
            v_all_cols_select
        FROM target_cols;

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
        DROP TABLE IF EXISTS temp_plan;
        RETURN QUERY
            SELECT r.row_id, '[]'::JSONB, 'ERROR'::import.set_result_status, SQLERRM
            FROM unnest(COALESCE(p_source_row_ids, ARRAY[]::INTEGER[])) AS r(row_id)
            UNION ALL
            SELECT NULL::INT, '[]'::JSONB, 'ERROR'::import.set_result_status, SQLERRM
            WHERE p_source_row_ids IS NULL;
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
        FROM unnest(COALESCE(p_source_row_ids, ARRAY[]::INTEGER[])) AS r(row_id)
        WHERE NOT EXISTS (SELECT 1 FROM temp_plan p, unnest(p.source_row_ids) s(id) WHERE s.id = r.row_id);
END;
$temporal_merge$;

COMMENT ON FUNCTION import.temporal_merge IS
'Orchestrates a set-based temporal merge operation. It generates a plan using temporal_merge_plan and then executes it.';


COMMIT;
