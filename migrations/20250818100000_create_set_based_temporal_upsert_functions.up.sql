-- Migration: create_set_based_temporal_upsert_functions
--
-- This migration introduces the initial stub functions for a new set-based
-- approach to handling temporal data inserts and updates. These functions
-- are intended to eventually replace the iterative, row-by-row functions
-- (e.g., batch_insert_or_replace_generic_valid_time_table).
--
-- The core idea is to process an entire batch of source data from a temporary
-- table in a single, holistic operation, which is expected to be significantly
-- more performant for large import jobs.
--
-- This initial version provides only the function signatures and a placeholder
-- implementation to allow for the parallel development of test cases.

BEGIN;

CREATE TYPE import.plan_operation_type AS ENUM ('INSERT', 'UPDATE', 'DELETE');

-- Defines the structure for a single operation in a temporal execution plan.
CREATE TYPE import.temporal_plan_op AS (
    source_row_id INTEGER,
    operation import.plan_operation_type,
    entity_id INT,
    old_valid_after DATE,
    new_valid_after DATE,
    new_valid_to DATE,
    data JSONB,
    relation public.allen_interval_relation
);

-- Planning Function for Insert or Replace
CREATE OR REPLACE FUNCTION import.plan_set_insert_or_replace_generic_valid_time_table(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_target_entity_id_column_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_source_entity_id_column_name TEXT,
    p_source_row_ids INTEGER[],
    p_ephemeral_columns TEXT[]
) RETURNS SETOF import.temporal_plan_op
LANGUAGE plpgsql STABLE AS $plan_set_insert_or_replace_generic_valid_time_table$
DECLARE
    v_sql TEXT;
    v_data_cols_jsonb_build TEXT;
BEGIN
    -- 1. Dynamically get the list of data columns from the target table to build a JSONB payload.
    -- These are all columns except the entity ID, temporal columns, and sql_saga era columns.
    -- The table alias 't' is used generically in the generated string.
    SELECT
        format('jsonb_build_object(%s)', string_agg(format('%L, t.%I', c.column_name, c.column_name), ', '))
    INTO
        v_data_cols_jsonb_build
    FROM
        information_schema.columns c
    WHERE
        c.table_schema = p_target_schema_name
        AND c.table_name = p_target_table_name
        AND c.column_name NOT IN (
            p_target_entity_id_column_name,
            'valid_after',
            'valid_to',
            'era_id',
            'era_name'
        );

    v_data_cols_jsonb_build := COALESCE(v_data_cols_jsonb_build, '''{}''::jsonb');

    -- 2. Construct and execute the main query to generate the execution plan.
    v_sql := format($SQL$
WITH
source_rows AS (
    SELECT
        t.row_id as source_row_id,
        t.%6$I as entity_id,
        t.valid_after,
        t.valid_to,
        jsonb_strip_nulls(%2$s) AS data_payload
    FROM %3$s.%4$s t
    WHERE (%5$L IS NULL OR t.row_id = ANY(%5$L))
      AND t.valid_after < t.valid_to
),
target_rows AS (
    SELECT
        t.%1$I as entity_id,
        t.valid_after,
        t.valid_to,
        %2$s AS data_payload
    FROM %7$s.%8$s t
    WHERE t.%1$I IN (SELECT DISTINCT entity_id FROM source_rows)
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
        CASE WHEN s.data_payload IS NOT NULL THEN s.data_payload ELSE t.data_payload END as data_payload,
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
      AND (t.data_payload IS NOT NULL OR s.data_payload IS NOT NULL) -- Filter out gaps
),
coalesced_timeline_segments AS (
    SELECT
        entity_id,
        MIN(valid_after) as valid_after,
        MAX(valid_to) as valid_to,
        (array_agg(data_payload ORDER BY priority, valid_after DESC))[1] as data_payload,
        (array_agg(source_row_id ORDER BY valid_after))[1] as source_row_id,
        (array_agg(t_valid_after ORDER BY valid_after) FILTER (WHERE t_valid_after IS NOT NULL))[1] as candidate_anchor,
        COUNT(*) as segments_in_group,
        (array_agg(priority ORDER BY valid_after)) as priorities
    FROM (
        SELECT *,
            SUM(CASE WHEN is_new_group THEN 1 ELSE 0 END) OVER (PARTITION BY entity_id ORDER BY valid_after) as group_id
        FROM (
            SELECT fss.*,
                COALESCE(LAG(fss.data_payload - %9$L::text[], 1) OVER (PARTITION BY fss.entity_id ORDER BY fss.valid_after) IS DISTINCT FROM (fss.data_payload - %9$L::text[]), true)
                as is_new_group
            FROM resolved_atomic_segments fss
        ) with_new_group_flag
    ) with_group_id
    GROUP BY entity_id, group_id
),
anchored_timeline_segments AS (
    SELECT f.*,
        CASE
            -- For REPLACE, an anchor is only valid if the resulting block contains original data (priority=2)...
            WHEN 2 = ANY(f.priorities) AND f.candidate_anchor IS NOT NULL THEN f.candidate_anchor
            -- ...OR it's a direct `equals` replacement, which is an UPDATE by convention.
            WHEN f.valid_after = f.candidate_anchor THEN f.candidate_anchor
            ELSE NULL
        END as anchor_t_valid_after
    FROM coalesced_timeline_segments f
),
diff AS (
    SELECT
        f.entity_id as f_entity_id, f.valid_after as f_after, f.valid_to as f_to, f.data_payload as f_data, f.source_row_id as f_source_row_id,
        t.entity_id as t_entity_id, t.valid_after as t_after, t.valid_to as t_to, t.data_payload as t_data,
        -- Rank update candidates. The one whose data matches the original target is rank 1 (the survivor).
        ROW_NUMBER() OVER(PARTITION BY t.entity_id, t.valid_after ORDER BY
            CASE WHEN (f.data_payload - %9$L::text[]) IS NOT DISTINCT FROM (t.data_payload - %9$L::text[])
            THEN 0 ELSE 1 END, f.valid_after
        ) as update_candidate_rank
    FROM anchored_timeline_segments f
    FULL OUTER JOIN target_rows t ON f.entity_id = t.entity_id AND f.anchor_t_valid_after = t.valid_after
    WHERE f.entity_id IS NULL -- A row from target_rows was deleted
       OR t.entity_id IS NULL -- A row from the final state is new
       OR (f.data_payload - %9$L::text[]) IS DISTINCT FROM (t.data_payload - %9$L::text[]) -- A row was updated (data changed)
       OR f.valid_to IS DISTINCT FROM t.valid_to -- A row was updated (timeline changed)
       OR f.valid_after IS DISTINCT FROM t.valid_after -- A row was updated (timeline changed, e.g. a merge)
    UNION ALL
    SELECT
        NULL, NULL, NULL, NULL, NULL,
        t.entity_id, t.valid_after, t.valid_to, t.data_payload,
        1 -- Not an update candidate, but needs a value for the column
    FROM target_rows t
    WHERE NOT EXISTS (
        SELECT 1 FROM coalesced_timeline_segments f
        WHERE f.entity_id = t.entity_id
          AND daterange(f.valid_after, f.valid_to, '(]') && daterange(t.valid_after, t.valid_to, '(]')
    )
),
plan AS (
    SELECT
        COALESCE(d.f_source_row_id, (
            SELECT s.source_row_id FROM source_rows s
            WHERE s.entity_id = COALESCE(d.f_entity_id, d.t_entity_id)
              AND (
                  daterange(s.valid_after, s.valid_to, '(]') && daterange(COALESCE(d.f_after, d.t_after), COALESCE(d.f_to, d.t_to), '(]')
                  OR
                  daterange(s.valid_after, s.valid_to, '(]') -|- daterange(COALESCE(d.f_after, d.t_after), COALESCE(d.f_to, d.t_to), '(]')
              )
            ORDER BY s.source_row_id
            LIMIT 1
        )) AS source_row_id,
        CASE
            WHEN d.f_after IS NULL THEN 'DELETE'::import.plan_operation_type
            WHEN d.t_after IS NULL THEN 'INSERT'::import.plan_operation_type
            -- Only the first fragment anchored to a target can be an UPDATE. Subsequent fragments are INSERTs.
            WHEN d.update_candidate_rank > 1 THEN 'INSERT'::import.plan_operation_type
            ELSE 'UPDATE'::import.plan_operation_type
        END as operation,
        COALESCE(d.f_entity_id, d.t_entity_id) as entity_id,
        -- `old_valid_after` is only populated for actual UPDATEs, otherwise it is NULL for INSERTs.
        CASE WHEN d.update_candidate_rank > 1 THEN NULL ELSE d.t_after END as old_valid_after,
        d.f_after as new_valid_after,
        d.f_to as new_valid_to,
        d.f_data as data
    FROM diff d
)
SELECT p.source_row_id, p.operation, p.entity_id, p.old_valid_after, p.new_valid_after, p.new_valid_to, p.data, rel.relation FROM plan p
LEFT JOIN LATERAL (
    SELECT rel.relation FROM (
        SELECT
            (CASE
                -- Naming convention: s is source, t is target. Relation describes s relative to t.
                -- Exact match
                WHEN s.valid_after = t.valid_after AND s.valid_to = t.valid_to THEN 'equals'

                -- s starts t, or is started by t
                WHEN s.valid_after = t.valid_after AND s.valid_to < t.valid_to THEN 'starts'
                WHEN s.valid_after = t.valid_after AND s.valid_to > t.valid_to THEN 'started_by'

                -- s finishes t, or is finished by t
                WHEN s.valid_after > t.valid_after AND s.valid_to = t.valid_to THEN 'finishes'
                WHEN s.valid_after < t.valid_after AND s.valid_to = t.valid_to THEN 'finished_by'

                -- s is during t, or contains t
                WHEN s.valid_after > t.valid_after AND s.valid_to < t.valid_to THEN 'during'
                WHEN s.valid_after < t.valid_after AND s.valid_to > t.valid_to THEN 'contains'

                -- s meets t, or is met by t
                WHEN s.valid_to = t.valid_after THEN 'meets'
                WHEN s.valid_after = t.valid_to THEN 'met_by'

                -- s overlaps t, or is overlapped by t
                WHEN s.valid_after < t.valid_after AND s.valid_to > t.valid_after AND s.valid_to < t.valid_to THEN 'overlaps'
                WHEN t.valid_after < s.valid_after AND t.valid_to > s.valid_after AND t.valid_to < s.valid_to THEN 'overlapped_by'

                -- Non-overlapping cases
                WHEN s.valid_to < t.valid_after THEN 'precedes'
                WHEN s.valid_after > t.valid_to THEN 'preceded_by'
            END)::public.allen_interval_relation as relation,
            -- For non-overlapping, distance is positive. For overlapping, it's negative.
            -- Infinity-safe version of GREATEST(s.valid_after - t.valid_to, t.valid_after - s.valid_to)
            GREATEST(
                CASE WHEN t.valid_to = 'infinity' THEN -2147483647 ELSE s.valid_after - t.valid_to END,
                CASE WHEN s.valid_to = 'infinity' THEN -2147483647 ELSE t.valid_after - s.valid_to END
            ) as distance
        FROM source_rows s
        JOIN target_rows t ON s.entity_id = t.entity_id
        WHERE s.source_row_id = p.source_row_id
    ) rel
    ORDER BY rel.distance
    LIMIT 1
) rel ON p.source_row_id IS NOT NULL
ORDER BY
    source_row_id,
    operation DESC, -- DELETEs first
    entity_id,
    COALESCE(new_valid_after, old_valid_after);
$SQL$,
        p_target_entity_id_column_name, -- 1
        v_data_cols_jsonb_build,        -- 2
        p_source_schema_name,           -- 3
        p_source_table_name,            -- 4
        p_source_row_ids,               -- 5
        p_source_entity_id_column_name, -- 6
        p_target_schema_name,           -- 7
        p_target_table_name,            -- 8
        p_ephemeral_columns             -- 9
    );

    RETURN QUERY EXECUTE v_sql;
END;
$plan_set_insert_or_replace_generic_valid_time_table$;

-- Main Orchestrator Function for Insert or Replace
CREATE OR REPLACE FUNCTION import.set_insert_or_replace_generic_valid_time_table(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_target_entity_id_column_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_source_entity_id_column_name TEXT,
    p_source_row_ids INTEGER[],
    p_ephemeral_columns TEXT[]
)
RETURNS TABLE (
    source_row_id INTEGER,
    upserted_record_ids INT[],
    status TEXT,
    error_message TEXT
)
LANGUAGE plpgsql VOLATILE AS $set_insert_or_replace_generic_valid_time_table$
DECLARE
    v_target_table_ident TEXT := format('%I.%I', p_target_schema_name, p_target_table_name);
    v_data_cols_ident TEXT;
    v_data_cols_select TEXT;
    v_update_set_clause TEXT;
BEGIN
    CREATE TEMP TABLE temp_plan (LIKE import.temporal_plan_op) ON COMMIT DROP;

    BEGIN
        INSERT INTO temp_plan
        SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(
            p_target_schema_name, p_target_table_name, p_target_entity_id_column_name,
            p_source_schema_name, p_source_table_name, p_source_entity_id_column_name,
            p_source_row_ids, p_ephemeral_columns
        );

        -- Get dynamic column lists for DML
        WITH data_cols AS (
            SELECT c.column_name
            FROM information_schema.columns c
            WHERE c.table_schema = p_target_schema_name
              AND c.table_name = p_target_table_name
              AND c.column_name NOT IN (
                  p_target_entity_id_column_name,
                  'valid_after', 'valid_to', 'era_id', 'era_name'
              )
            ORDER BY c.ordinal_position
        )
        SELECT
            string_agg(format('%I', column_name), ', '),
            string_agg(format('jpr.%I', column_name), ', '),
            string_agg(format('%I = jpr.%I', column_name, column_name), ', ')
        INTO
            v_data_cols_ident,
            v_data_cols_select,
            v_update_set_clause
        FROM data_cols;

        -- Execute the plan using DEFERRED constraints. This is critical for two reasons:
        -- 1. Exclusion Constraints: The DML operations may create temporary, harmless
        --    overlaps (e.g., an INSERT followed by an UPDATE that shortens an existing
        --    record). Deferring exclusion constraints allows these temporary states.
        -- 2. Temporal Foreign Keys (sql_saga): sql_saga's triggers are also deferred.
        --    They validate the timeline's integrity at the end of the transaction.
        --
        -- The DML operations MUST run in the "add-then-modify" order (INSERT -> UPDATE -> DELETE).
        -- This ensures that when sql_saga's triggers eventually run, their data snapshots
        -- (taken at the start of each DML statement) see a consistent state of the timeline,
        -- preventing incorrect foreign key violation errors.
        SET CONSTRAINTS ALL DEFERRED;

        -- 1. Execute INSERT operations
        IF v_data_cols_ident IS NOT NULL THEN
            EXECUTE format($$ INSERT INTO %1$s (%2$I, valid_after, valid_to, %3$s)
                SELECT p.entity_id, p.new_valid_after, p.new_valid_to, %4$s
                FROM temp_plan p, LATERAL jsonb_populate_record(null::%1$s, p.data) AS jpr
                WHERE p.operation = 'INSERT';
            $$, v_target_table_ident, p_target_entity_id_column_name, v_data_cols_ident, v_data_cols_select);
        ELSE
             EXECUTE format($$ INSERT INTO %1$s (%2$I, valid_after, valid_to)
                SELECT p.entity_id, p.new_valid_after, p.new_valid_to FROM temp_plan p WHERE p.operation = 'INSERT';
            $$, v_target_table_ident, p_target_entity_id_column_name);
        END IF;

        -- 2. Execute UPDATE operations
        IF v_update_set_clause IS NOT NULL THEN
            EXECUTE format($$ UPDATE %1$s t SET valid_after = p.new_valid_after, valid_to = p.new_valid_to, %2$s
                FROM temp_plan p, LATERAL jsonb_populate_record(null::%1$s, p.data) AS jpr
                WHERE p.operation = 'UPDATE' AND t.%3$I = p.entity_id AND t.valid_after = p.old_valid_after;
            $$, v_target_table_ident, v_update_set_clause, p_target_entity_id_column_name);
        ELSE
            EXECUTE format($$ UPDATE %1$s t SET valid_after = p.new_valid_after, valid_to = p.new_valid_to
                FROM temp_plan p
                WHERE p.operation = 'UPDATE' AND t.%2$I = p.entity_id AND t.valid_after = p.old_valid_after;
            $$, v_target_table_ident, p_target_entity_id_column_name);
        END IF;

        -- 3. Execute DELETE operations
        EXECUTE format($$ DELETE FROM %1$s t USING temp_plan p
            WHERE p.operation = 'DELETE' AND t.%2$I = p.entity_id AND t.valid_after = p.old_valid_after;
        $$, v_target_table_ident, p_target_entity_id_column_name);

        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY
            SELECT r.row_id, ARRAY[]::INT[], 'ERROR'::TEXT, SQLERRM
            FROM unnest(COALESCE(p_source_row_ids, ARRAY[]::INTEGER[])) AS r(row_id)
            UNION ALL
            SELECT NULL::INT, ARRAY[]::INT[], 'ERROR'::TEXT, SQLERRM
            WHERE p_source_row_ids IS NULL;
        RETURN;
    END;

    RETURN QUERY
        -- Report success for source rows that generated plan operations
        SELECT tp.source_row_id, ARRAY[]::INT[], 'SUCCESS'::TEXT, NULL::TEXT
        FROM temp_plan tp WHERE tp.source_row_id IS NOT NULL GROUP BY tp.source_row_id
        UNION ALL
        -- Report success for source rows that were processed but generated no plan operations
        SELECT r.row_id, ARRAY[]::INT[], 'SUCCESS'::TEXT, NULL::TEXT
        FROM unnest(COALESCE(p_source_row_ids, ARRAY[]::INTEGER[])) as r(row_id)
        WHERE NOT EXISTS (SELECT 1 FROM temp_plan tp WHERE tp.source_row_id = r.row_id);
END;
$set_insert_or_replace_generic_valid_time_table$;

COMMENT ON FUNCTION import.set_insert_or_replace_generic_valid_time_table IS
'Orchestrates a set-based temporal "insert or replace" operation. It generates a plan using plan_set_... and then executes it.
- p_target_schema_name: Schema of the target table.
- p_target_table_name: Name of the target temporal table.
- p_target_entity_id_column_name: Name of the entity ID column in the target table (e.g., ''id'').
- p_source_schema_name: Schema of the source table.
- p_source_table_name: Name of the source table containing the new data.
- p_source_entity_id_column_name: Name of the entity ID column in the source table (e.g., ''legal_unit_id'').
- p_source_row_ids: Optional array of row_ids to process from the source table. If NULL, process all rows.
- p_ephemeral_columns: Array of column names to be excluded from data equivalence checks.';


-- Planning Function for Insert or Update
CREATE OR REPLACE FUNCTION import.plan_set_insert_or_update_generic_valid_time_table(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_target_entity_id_column_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_source_entity_id_column_name TEXT,
    p_source_row_ids INTEGER[],
    p_ephemeral_columns TEXT[]
) RETURNS SETOF import.temporal_plan_op
LANGUAGE plpgsql STABLE AS $plan_set_insert_or_update_generic_valid_time_table$
DECLARE
    v_sql TEXT;
    v_data_cols_jsonb_build TEXT;
BEGIN
    -- 1. Dynamically get the list of data columns from the target table to build a JSONB payload.
    SELECT
        format('jsonb_build_object(%s)', string_agg(format('%L, t.%I', c.column_name, c.column_name), ', '))
    INTO
        v_data_cols_jsonb_build
    FROM
        information_schema.columns c
    WHERE
        c.table_schema = p_target_schema_name
        AND c.table_name = p_target_table_name
        AND c.column_name NOT IN (
            p_target_entity_id_column_name,
            'valid_after',
            'valid_to',
            'era_id',
            'era_name'
        );

    v_data_cols_jsonb_build := COALESCE(v_data_cols_jsonb_build, '''{}''::jsonb');

    -- 2. Construct and execute the main query to generate the execution plan.
    v_sql := format($SQL$
WITH
source_rows AS (
    SELECT
        t.row_id as source_row_id,
        t.%6$I as entity_id,
        t.valid_after,
        t.valid_to,
        jsonb_strip_nulls(%2$s) AS data_payload
    FROM %3$s.%4$s t
    WHERE (%5$L IS NULL OR t.row_id = ANY(%5$L))
      AND t.valid_after < t.valid_to
),
target_rows AS (
    SELECT
        t.%1$I as entity_id,
        t.valid_after,
        t.valid_to,
        %2$s AS data_payload
    FROM %7$s.%8$s t
    WHERE t.%1$I IN (SELECT DISTINCT entity_id FROM source_rows)
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
        CASE
            WHEN s.data_payload IS NOT NULL THEN (COALESCE(t.data_payload, '{}'::jsonb) || s.data_payload)
            ELSE t.data_payload
        END as data_payload,
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
      AND (t.data_payload IS NOT NULL OR s.data_payload IS NOT NULL) -- Filter out gaps
),
coalesced_timeline_segments AS (
    SELECT
        entity_id,
        MIN(valid_after) as valid_after,
        MAX(valid_to) as valid_to,
        (array_agg(data_payload ORDER BY priority, valid_after DESC))[1] as data_payload,
        (array_agg(source_row_id ORDER BY valid_after))[1] as source_row_id,
        (array_agg(t_valid_after ORDER BY valid_after) FILTER (WHERE t_valid_after IS NOT NULL))[1] as candidate_anchor,
        COUNT(*) as segments_in_group
    FROM (
        SELECT *,
            SUM(CASE WHEN is_new_group THEN 1 ELSE 0 END) OVER (PARTITION BY entity_id ORDER BY valid_after) as group_id
        FROM (
            SELECT fss.*,
                COALESCE(LAG(fss.data_payload - %9$L::text[], 1) OVER (PARTITION BY fss.entity_id ORDER BY fss.valid_after) IS DISTINCT FROM (fss.data_payload - %9$L::text[]), true)
                as is_new_group
            FROM resolved_atomic_segments fss
        ) with_new_group_flag
    ) with_group_id
    GROUP BY entity_id, group_id
),
anchored_timeline_segments AS (
    SELECT f.*,
        CASE
            -- Case 1: The coalesced block starts at the same time as an original record. This is a clear UPDATE.
            WHEN f.valid_after = f.candidate_anchor THEN f.candidate_anchor
            -- Case 2: It's a MERGE. The start time is different, but it was formed by coalescing
            -- multiple adjacent segments (including an original target segment). This should also be an UPDATE.
            WHEN f.valid_after != f.candidate_anchor AND f.candidate_anchor IS NOT NULL AND f.segments_in_group > 1 THEN f.candidate_anchor
            -- All other cases are INSERTs (no anchor).
            ELSE NULL
        END as anchor_t_valid_after
    FROM coalesced_timeline_segments f
),
diff AS (
    SELECT
        f.entity_id as f_entity_id, f.valid_after as f_after, f.valid_to as f_to, f.data_payload as f_data, f.source_row_id as f_source_row_id,
        t.entity_id as t_entity_id, t.valid_after as t_after, t.valid_to as t_to, t.data_payload as t_data,
        -- If multiple final segments are anchored to the same target, only one can be an UPDATE.
        -- We rank them and the plan will designate only rank=1 as the UPDATE.
        ROW_NUMBER() OVER(PARTITION BY t.entity_id, t.valid_after ORDER BY f.valid_after) as update_candidate_rank
    FROM anchored_timeline_segments f
    FULL OUTER JOIN target_rows t ON f.entity_id = t.entity_id AND f.anchor_t_valid_after = t.valid_after
    WHERE f.entity_id IS NULL -- A row from target_rows was deleted
       OR t.entity_id IS NULL -- A row from the final state is new
       OR (f.data_payload - %9$L::text[]) IS DISTINCT FROM (t.data_payload - %9$L::text[]) -- A row was updated (data changed)
       OR f.valid_to IS DISTINCT FROM t.valid_to -- A row was updated (timeline changed)
       OR f.valid_after IS DISTINCT FROM t.valid_after -- A row was updated (timeline changed, e.g. a merge)
    UNION ALL
    SELECT
        NULL, NULL, NULL, NULL, NULL,
        t.entity_id, t.valid_after, t.valid_to, t.data_payload,
        1 -- Not an update candidate, but needs a value for the column
    FROM target_rows t
    WHERE NOT EXISTS (
        SELECT 1 FROM coalesced_timeline_segments f
        WHERE f.entity_id = t.entity_id
          AND daterange(f.valid_after, f.valid_to, '(]') && daterange(t.valid_after, t.valid_to, '(]')
    )
),
plan AS (
    SELECT
        COALESCE(d.f_source_row_id, (
            SELECT s.source_row_id FROM source_rows s
            WHERE s.entity_id = COALESCE(d.f_entity_id, d.t_entity_id)
              AND (
                  daterange(s.valid_after, s.valid_to, '(]') && daterange(COALESCE(d.f_after, d.t_after), COALESCE(d.f_to, d.t_to), '(]')
                  OR
                  daterange(s.valid_after, s.valid_to, '(]') -|- daterange(COALESCE(d.f_after, d.t_after), COALESCE(d.f_to, d.t_to), '(]')
              )
            ORDER BY s.source_row_id
            LIMIT 1
        )) AS source_row_id,
        CASE
            WHEN d.f_after IS NULL THEN 'DELETE'::import.plan_operation_type
            WHEN d.t_after IS NULL THEN 'INSERT'::import.plan_operation_type
            -- Only the first fragment anchored to a target can be an UPDATE. Subsequent fragments are INSERTs.
            WHEN d.update_candidate_rank > 1 THEN 'INSERT'::import.plan_operation_type
            ELSE 'UPDATE'::import.plan_operation_type
        END as operation,
        COALESCE(d.f_entity_id, d.t_entity_id) as entity_id,
        -- `old_valid_after` is only populated for actual UPDATEs, otherwise it is NULL for INSERTs.
        CASE WHEN d.update_candidate_rank > 1 THEN NULL ELSE d.t_after END as old_valid_after,
        d.f_after as new_valid_after,
        d.f_to as new_valid_to,
        d.f_data as data
    FROM diff d
)
SELECT p.source_row_id, p.operation, p.entity_id, p.old_valid_after, p.new_valid_after, p.new_valid_to, p.data, rel.relation FROM plan p
LEFT JOIN LATERAL (
    SELECT rel.relation FROM (
        SELECT
            (CASE
                -- Naming convention: s is source, t is target. Relation describes s relative to t.
                -- Exact match
                WHEN s.valid_after = t.valid_after AND s.valid_to = t.valid_to THEN 'equals'

                -- s starts t, or is started by t
                WHEN s.valid_after = t.valid_after AND s.valid_to < t.valid_to THEN 'starts'
                WHEN s.valid_after = t.valid_after AND s.valid_to > t.valid_to THEN 'started_by'

                -- s finishes t, or is finished by t
                WHEN s.valid_after > t.valid_after AND s.valid_to = t.valid_to THEN 'finishes'
                WHEN s.valid_after < t.valid_after AND s.valid_to = t.valid_to THEN 'finished_by'

                -- s is during t, or contains t
                WHEN s.valid_after > t.valid_after AND s.valid_to < t.valid_to THEN 'during'
                WHEN s.valid_after < t.valid_after AND s.valid_to > t.valid_to THEN 'contains'

                -- s meets t, or is met by t
                WHEN s.valid_to = t.valid_after THEN 'meets'
                WHEN s.valid_after = t.valid_to THEN 'met_by'

                -- s overlaps t, or is overlapped by t
                WHEN s.valid_after < t.valid_after AND s.valid_to > t.valid_after AND s.valid_to < t.valid_to THEN 'overlaps'
                WHEN t.valid_after < s.valid_after AND t.valid_to > s.valid_after AND t.valid_to < s.valid_to THEN 'overlapped_by'

                -- Non-overlapping cases
                WHEN s.valid_to < t.valid_after THEN 'precedes'
                WHEN s.valid_after > t.valid_to THEN 'preceded_by'
            END)::public.allen_interval_relation as relation,
            -- For non-overlapping, distance is positive. For overlapping, it's negative.
            -- Infinity-safe version of GREATEST(s.valid_after - t.valid_to, t.valid_after - s.valid_to)
            GREATEST(
                CASE WHEN t.valid_to = 'infinity' THEN -2147483647 ELSE s.valid_after - t.valid_to END,
                CASE WHEN s.valid_to = 'infinity' THEN -2147483647 ELSE t.valid_after - s.valid_to END
            ) as distance
        FROM source_rows s
        JOIN target_rows t ON s.entity_id = t.entity_id
        WHERE s.source_row_id = p.source_row_id
    ) rel
    ORDER BY rel.distance
    LIMIT 1
) rel ON p.source_row_id IS NOT NULL
ORDER BY
    source_row_id,
    operation DESC, -- DELETEs first
    entity_id,
    COALESCE(new_valid_after, old_valid_after);
$SQL$,
        p_target_entity_id_column_name, -- 1
        v_data_cols_jsonb_build,        -- 2
        p_source_schema_name,           -- 3
        p_source_table_name,            -- 4
        p_source_row_ids,               -- 5
        p_source_entity_id_column_name, -- 6
        p_target_schema_name,           -- 7
        p_target_table_name,            -- 8
        p_ephemeral_columns             -- 9
    );

    RETURN QUERY EXECUTE v_sql;
END;
$plan_set_insert_or_update_generic_valid_time_table$;


-- Main Orchestrator Function for Insert or Update
CREATE OR REPLACE FUNCTION import.set_insert_or_update_generic_valid_time_table(
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_target_entity_id_column_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_source_entity_id_column_name TEXT,
    p_source_row_ids INTEGER[],
    p_ephemeral_columns TEXT[]
)
RETURNS TABLE (
    source_row_id INTEGER,
    upserted_record_ids INT[],
    status TEXT,
    error_message TEXT
)
LANGUAGE plpgsql VOLATILE AS $set_insert_or_update_generic_valid_time_table$
DECLARE
    v_target_table_ident TEXT := format('%I.%I', p_target_schema_name, p_target_table_name);
    v_data_cols_ident TEXT;
    v_data_cols_select TEXT;
    v_update_set_clause TEXT;
BEGIN
    CREATE TEMP TABLE temp_plan (LIKE import.temporal_plan_op) ON COMMIT DROP;

    BEGIN
        INSERT INTO temp_plan
        SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(
            p_target_schema_name, p_target_table_name, p_target_entity_id_column_name,
            p_source_schema_name, p_source_table_name, p_source_entity_id_column_name,
            p_source_row_ids, p_ephemeral_columns
        );

        -- Get dynamic column lists for DML
        WITH data_cols AS (
            SELECT c.column_name
            FROM information_schema.columns c
            WHERE c.table_schema = p_target_schema_name
              AND c.table_name = p_target_table_name
              AND c.column_name NOT IN (
                  p_target_entity_id_column_name,
                  'valid_after', 'valid_to', 'era_id', 'era_name'
              )
            ORDER BY c.ordinal_position
        )
        SELECT
            string_agg(format('%I', column_name), ', '),
            string_agg(format('jpr.%I', column_name), ', '),
            string_agg(format('%I = jpr.%I', column_name, column_name), ', ')
        INTO
            v_data_cols_ident,
            v_data_cols_select,
            v_update_set_clause
        FROM data_cols;

        -- Execute the plan using DEFERRED constraints. This is critical for two reasons:
        -- 1. Exclusion Constraints: The DML operations may create temporary, harmless
        --    overlaps (e.g., an INSERT followed by an UPDATE that shortens an existing
        --    record). Deferring exclusion constraints allows these temporary states.
        -- 2. Temporal Foreign Keys (sql_saga): sql_saga's triggers are also deferred.
        --    They validate the timeline's integrity at the end of the transaction.
        --
        -- The DML operations MUST run in the "add-then-modify" order (INSERT -> UPDATE -> DELETE).
        -- This ensures that when sql_saga's triggers eventually run, their data snapshots
        -- (taken at the start of each DML statement) see a consistent state of the timeline,
        -- preventing incorrect foreign key violation errors.
        SET CONSTRAINTS ALL DEFERRED;

        -- 1. Execute INSERT operations
        IF v_data_cols_ident IS NOT NULL THEN
            EXECUTE format($$ INSERT INTO %1$s (%2$I, valid_after, valid_to, %3$s)
                SELECT p.entity_id, p.new_valid_after, p.new_valid_to, %4$s
                FROM temp_plan p, LATERAL jsonb_populate_record(null::%1$s, p.data) AS jpr
                WHERE p.operation = 'INSERT';
            $$, v_target_table_ident, p_target_entity_id_column_name, v_data_cols_ident, v_data_cols_select);
        ELSE
             EXECUTE format($$ INSERT INTO %1$s (%2$I, valid_after, valid_to)
                SELECT p.entity_id, p.new_valid_after, p.new_valid_to FROM temp_plan p WHERE p.operation = 'INSERT';
            $$, v_target_table_ident, p_target_entity_id_column_name);
        END IF;

        -- 2. Execute UPDATE operations
        IF v_update_set_clause IS NOT NULL THEN
            EXECUTE format($$ UPDATE %1$s t SET valid_after = p.new_valid_after, valid_to = p.new_valid_to, %2$s
                FROM temp_plan p, LATERAL jsonb_populate_record(null::%1$s, p.data) AS jpr
                WHERE p.operation = 'UPDATE' AND t.%3$I = p.entity_id AND t.valid_after = p.old_valid_after;
            $$, v_target_table_ident, v_update_set_clause, p_target_entity_id_column_name);
        ELSE
            EXECUTE format($$ UPDATE %1$s t SET valid_after = p.new_valid_after, valid_to = p.new_valid_to
                FROM temp_plan p
                WHERE p.operation = 'UPDATE' AND t.%2$I = p.entity_id AND t.valid_after = p.old_valid_after;
            $$, v_target_table_ident, p_target_entity_id_column_name);
        END IF;

        -- 3. Execute DELETE operations
        EXECUTE format($$ DELETE FROM %1$s t USING temp_plan p
            WHERE p.operation = 'DELETE' AND t.%2$I = p.entity_id AND t.valid_after = p.old_valid_after;
        $$, v_target_table_ident, p_target_entity_id_column_name);

        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY
            SELECT r.row_id, ARRAY[]::INT[], 'ERROR'::TEXT, SQLERRM
            FROM unnest(COALESCE(p_source_row_ids, ARRAY[]::INTEGER[])) AS r(row_id)
            UNION ALL
            SELECT NULL::INT, ARRAY[]::INT[], 'ERROR'::TEXT, SQLERRM
            WHERE p_source_row_ids IS NULL;
        RETURN;
    END;

    RETURN QUERY
        -- Report success for source rows that generated plan operations
        SELECT tp.source_row_id, ARRAY[]::INT[], 'SUCCESS'::TEXT, NULL::TEXT
        FROM temp_plan tp WHERE tp.source_row_id IS NOT NULL GROUP BY tp.source_row_id
        UNION ALL
        -- Report success for source rows that were processed but generated no plan operations
        SELECT r.row_id, ARRAY[]::INT[], 'SUCCESS'::TEXT, NULL::TEXT
        FROM unnest(COALESCE(p_source_row_ids, ARRAY[]::INTEGER[])) as r(row_id)
        WHERE NOT EXISTS (SELECT 1 FROM temp_plan tp WHERE tp.source_row_id = r.row_id);
END;
$set_insert_or_update_generic_valid_time_table$;

COMMENT ON FUNCTION import.set_insert_or_update_generic_valid_time_table IS
'Orchestrates a set-based temporal "insert or update" operation. It generates a plan using plan_set_... and then executes it.
- p_target_schema_name: Schema of the target table.
- p_target_table_name: Name of the target temporal table.
- p_target_entity_id_column_name: Name of the entity ID column in the target table (e.g., ''id'').
- p_source_schema_name: Schema of the source table.
- p_source_table_name: Name of the source table containing the new data.
- p_source_entity_id_column_name: Name of the entity ID column in the source table (e.g., ''legal_unit_id'').
- p_source_row_ids: Optional array of row_ids to process from the source table. If NULL, process all rows.
- p_ephemeral_columns: Array of column names to be excluded from data equivalence checks.';


COMMIT;
