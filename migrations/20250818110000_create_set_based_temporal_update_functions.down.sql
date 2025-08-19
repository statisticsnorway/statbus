-- Migration: create_set_based_temporal_update_functions (Down)
--
-- Reverts the creation of the set-based temporal update functions.

BEGIN;

DROP FUNCTION IF EXISTS import.set_insert_or_update_generic_valid_time_table(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER[], TEXT[]);
DROP FUNCTION IF EXISTS import.plan_set_insert_or_update_generic_valid_time_table(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER[], TEXT[]);

COMMIT;
