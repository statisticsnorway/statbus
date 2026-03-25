-- Down Migration 20260325011559: virtual_physical_partition_mapping_with_auto_tune
-- Restore hardcoded 256 modulus.
BEGIN;

-- Restore hash functions with hardcoded 256
CREATE OR REPLACE FUNCTION public.report_partition_seq(p_unit_type text, p_unit_id integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $report_partition_seq$
    SELECT abs(hashtext(p_unit_type || ':' || p_unit_id::text)) % 256;
$report_partition_seq$;

CREATE OR REPLACE FUNCTION public.report_partition_seq(p_unit_type statistical_unit_type, p_unit_id integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $report_partition_seq$
    SELECT abs(hashtext(p_unit_type::text || ':' || p_unit_id::text)) % 256;
$report_partition_seq$;

-- Restore all derive/flush functions from \sf dumps
-- (These are restored to the state from the snapshot migration, which is the previous migration)
-- The snapshot migration's down migration will restore them further if needed.

-- Drop auto-tune
DROP PROCEDURE IF EXISTS admin.adjust_report_partition_modulus();

-- Drop function and column
DROP FUNCTION IF EXISTS public.get_report_partition_modulus();
ALTER TABLE public.settings DROP COLUMN IF EXISTS report_partition_modulus;

END;
