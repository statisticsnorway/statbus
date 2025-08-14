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
    data JSONB
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
LANGUAGE plpgsql VOLATILE AS $plan_set_insert_or_replace_generic_valid_time_table$
BEGIN
    RAISE NOTICE '[plan_set_insert_or_replace] Not yet implemented. Placeholder function called.';
    -- Stub implementation returns an empty plan.
    RETURN;
END;
$plan_set_insert_or_replace_generic_valid_time_table$;

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
LANGUAGE plpgsql VOLATILE AS $plan_set_insert_or_update_generic_valid_time_table$
BEGIN
    RAISE NOTICE '[plan_set_insert_or_update] Not yet implemented. Placeholder function called.';
    RETURN;
END;
$plan_set_insert_or_update_generic_valid_time_table$;


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
BEGIN
    RAISE NOTICE '[set_insert_or_replace] Not yet implemented. This function will orchestrate the plan and process stages.';

    -- In the final version, this function will:
    -- 1. Call plan_set_insert_or_replace_generic_valid_time_table(...)
    -- 2. Create a temporary plan table from the results.
    -- 3. Execute the plan (DELETEs, UPDATEs, INSERTs) against the target table.
    -- 4. Return the results.

    RETURN QUERY SELECT 1::INTEGER, ARRAY[]::INT[], 'SUCCESS'::TEXT, NULL::TEXT WHERE false;
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
BEGIN
    RAISE NOTICE '[set_insert_or_update] Not yet implemented. This function will orchestrate the plan and process stages.';
    RETURN QUERY SELECT 1::INTEGER, ARRAY[]::INT[], 'SUCCESS'::TEXT, NULL::TEXT WHERE false;
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
