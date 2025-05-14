BEGIN;

DROP FUNCTION IF EXISTS import.batch_insert_or_update_generic_valid_time_table(
    TEXT, -- p_target_schema_name
    TEXT, -- p_target_table_name
    TEXT, -- p_source_schema_name
    TEXT, -- p_source_table_name
    TEXT, -- p_source_row_id_column_name
    JSONB, -- p_unique_columns
    TEXT[], -- p_temporal_columns
    TEXT[], -- p_ephemeral_columns
    TEXT[], -- p_generated_columns_override
    TEXT -- p_id_column_name
);

COMMIT;
