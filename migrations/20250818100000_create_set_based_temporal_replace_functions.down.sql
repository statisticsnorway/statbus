-- Migration: create_set_based_temporal_replace_functions (Down)
--
-- Reverts the creation of the set-based temporal replace functions and types.

BEGIN;

DROP FUNCTION IF EXISTS import.set_insert_or_replace_generic_valid_time_table(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER[], TEXT[]);
DROP FUNCTION IF EXISTS import.plan_set_insert_or_replace_generic_valid_time_table(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER[], TEXT[]);
DROP TYPE IF EXISTS import.temporal_plan_op;
DROP TYPE IF EXISTS import.plan_operation_type;

COMMIT;
